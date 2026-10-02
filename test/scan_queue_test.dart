import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:delego/api/api_client.dart';
import 'package:delego/api/scan_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi extends ApiClient {
  FakeApi() : super(baseUrl: 'http://test');

  String? tok = 'tok';
  final sent = <Map<String, String>>[];

  /// Return a response, or throw to simulate network / auth failures.
  Future<http.Response> Function(Map<String, String> form) handler =
      (_) async => ok('served');

  @override
  Future<String?> get token async => tok;

  @override
  Future<http.Response> postForm(String path, Map<String, String> form) {
    sent.add(form);
    return handler(form);
  }
}

http.Response ok(String result, {String? name}) => http.Response(
    jsonEncode({'result': result, if (name != null) 'name': name}), 200);

Future<ScanQueue> makeQueue(FakeApi api,
    {StreamController<List<ConnectivityResult>>? conn}) async {
  final q = ScanQueue(
    api,
    connectivity: conn?.stream ?? const Stream.empty(),
    timeout: const Duration(milliseconds: 200),
    retryEvery: const Duration(hours: 1),
  );
  await q.start();
  return q;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ScanOutcome> scan(ScanQueue q, String id,
          {String meal = 'lunch', String diet = 'veg'}) =>
      q.post(delegateId: id, meal: meal, diet: diet);

  test('online scan: served, nothing queued, extra fields sent', () async {
    final api = FakeApi()..handler = (_) async => ok('served', name: 'Asha');
    final q = await makeQueue(api);

    final o = await scan(q, 'D1');
    expect(o.kind, ScanKind.served);
    expect(o.name, 'Asha');
    expect(q.pendingCount, 0);
    expect(api.sent.single['diet'], 'veg');
    expect(api.sent.single['scanned_at'], isNotNull);
    q.dispose();
  });

  test('server duplicate is shown, not queued', () async {
    final api = FakeApi()..handler = (_) async => ok('duplicate');
    final q = await makeQueue(api);
    expect((await scan(q, 'D1')).kind, ScanKind.duplicate);
    expect(q.pendingCount, 0);
    q.dispose();
  });

  test('404 / 422 / 403 / 401 are not queued', () async {
    final api = FakeApi();
    final q = await makeQueue(api);

    api.handler = (_) async => http.Response('{"detail":"nope"}', 404);
    var o = await scan(q, 'X');
    expect(o.kind, ScanKind.rejected);
    expect(o.message, 'nope');

    api.handler = (_) async => http.Response('{}', 422);
    expect((await scan(q, 'X')).kind, ScanKind.rejected);

    api.handler = (_) async => throw Forbidden();
    expect((await scan(q, 'X')).kind, ScanKind.denied);

    api.handler = (_) async => throw SessionExpired();
    expect((await scan(q, 'X')).kind, ScanKind.denied);

    expect(q.pendingCount, 0);
    q.dispose();
  });

  test('network error, timeout and 5xx are saved to the queue', () async {
    final api = FakeApi();
    final q = await makeQueue(api);

    api.handler = (_) async => throw Exception('no route');
    expect((await scan(q, 'A')).kind, ScanKind.queued);

    api.handler = (_) => Completer<http.Response>().future; // never answers
    expect((await scan(q, 'B')).kind, ScanKind.queued);

    api.handler = (_) async => http.Response('boom', 503);
    expect((await scan(q, 'C')).kind, ScanKind.queued);

    expect(q.pendingCount, 3);
    expect(q.offline, isTrue);
    q.dispose();
  });

  test('offline: same delegate+meal is flagged locally, other meal is not',
      () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);

    expect((await scan(q, 'A')).kind, ScanKind.queued);
    final dup = await scan(q, 'A');
    expect(dup.kind, ScanKind.duplicate);
    expect(dup.localDuplicate, isTrue);
    expect(q.pendingCount, 1);

    expect((await scan(q, 'A', meal: 'breakfast')).kind, ScanKind.queued);
    expect(q.pendingCount, 2);
    q.dispose();
  });

  test('pendingFor counts by meal and diet', () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);
    await scan(q, 'A', diet: 'veg');
    await scan(q, 'B', diet: 'jain');
    await scan(q, 'C', diet: 'veg', meal: 'breakfast');

    expect(q.pendingFor('lunch'), 2);
    expect(q.pendingFor('lunch', diet: 'veg'), 1);
    expect(q.pendingFor('breakfast'), 1);
    q.dispose();
  });

  test('flush sends in order and treats duplicate as synced', () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);
    await scan(q, 'A');
    await scan(q, 'B');
    await scan(q, 'C');

    api.sent.clear();
    api.handler =
        (f) async => ok(f['delegate_id'] == 'B' ? 'duplicate' : 'served');
    await q.flush();

    expect(api.sent.map((f) => f['delegate_id']), ['A', 'B', 'C']);
    expect(q.pendingCount, 0);
    expect(q.offline, isFalse);
    q.dispose();
  });

  test('flush stops at the first network failure and keeps the rest',
      () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);
    await scan(q, 'A');
    await scan(q, 'B');
    await scan(q, 'C');

    api.sent.clear();
    api.handler = (f) async =>
        f['delegate_id'] == 'B' ? http.Response('x', 502) : ok('served');
    await q.flush();

    expect(api.sent.map((f) => f['delegate_id']), ['A', 'B']);
    expect(q.pending.map((r) => r.delegateId), ['B', 'C']);
    q.dispose();
  });

  test('a rejected saved scan is dropped from the queue and announced',
      () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);
    await scan(q, 'BAD');
    await scan(q, 'GOOD');

    final msgs = <String>[];
    q.rejections.listen(msgs.add);

    api.handler = (f) async => f['delegate_id'] == 'BAD'
        ? http.Response('{"detail":"Delegate not found"}', 404)
        : ok('served');
    await q.flush();
    await Future<void>.delayed(Duration.zero);

    expect(q.pendingCount, 0);
    expect(msgs.single, contains('BAD'));
    expect(q.today.firstWhere((r) => r.delegateId == 'BAD').state,
        ScanState.rejected);
    q.dispose();
  });

  test('401/403 during flush keeps scans queued and sets a reason', () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);
    await scan(q, 'A');
    await scan(q, 'B');

    api.handler = (_) async => throw Forbidden();
    await q.flush();
    expect(q.pendingCount, 2);
    expect(q.blockedReason, contains('access'));

    // Access restored: sync resumes and the reason clears.
    api.handler = (_) async => ok('served');
    await q.flush();
    expect(q.pendingCount, 0);
    expect(q.blockedReason, isNull);
    q.dispose();
  });

  test('no token: flush does not hit the server', () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);
    await scan(q, 'A');

    api
      ..tok = null
      ..sent.clear();
    await q.flush();
    expect(api.sent, isEmpty);
    expect(q.pendingCount, 1);
    expect(q.blockedReason, isNotNull);
    q.dispose();
  });

  test('queue survives an app restart', () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q1 = await makeQueue(api);
    await scan(q1, 'A');
    await scan(q1, 'B', diet: 'jain');
    q1.dispose();

    final q2 = await makeQueue(FakeApi()..handler = (_) async => throw 'down');
    expect(q2.pending.map((r) => r.delegateId), ['A', 'B']);
    expect(q2.pending.last.diet, 'jain');
    q2.dispose();
  });

  test('connectivity returning triggers a flush', () async {
    final conn = StreamController<List<ConnectivityResult>>();
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api, conn: conn);
    await scan(q, 'A');
    expect(q.pendingCount, 1);

    api.handler = (_) async => ok('served');
    conn.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(q.pendingCount, 0);
    q.dispose();
    await conn.close();
  });

  test('no connectivity: scan is saved without waiting on the network',
      () async {
    final conn = StreamController<List<ConnectivityResult>>();
    final api = FakeApi();
    final q = await makeQueue(api, conn: conn);

    conn.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    api.sent.clear();

    expect((await scan(q, 'A')).kind, ScanKind.queued);
    expect(api.sent, isEmpty);
    q.dispose();
    await conn.close();
  });

  test('clearAll empties the queue', () async {
    final api = FakeApi()..handler = (_) async => throw Exception('down');
    final q = await makeQueue(api);
    await scan(q, 'A');
    await q.clearAll();
    expect(q.pendingCount, 0);
    q.dispose();
  });
}
