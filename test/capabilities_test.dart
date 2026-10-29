import 'dart:convert';

import 'package:delego/api/api_client.dart';
import 'package:delego/auth/capabilities.dart';
import 'package:delego/auth/permission_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What GET /delegates/me returns for each role/team combination.
const _serverProfiles = <String, ({String role, List<String> permissions})>{
  'delegate': (
    role: 'delegate',
    permissions: ['badge.view', 'guides.view'],
  ),
  'eb': (
    role: 'eb',
    permissions: ['badge.view', 'eb.tools', 'guides.view'],
  ),
  'oc': (
    role: 'oc',
    permissions: ['badge.view', 'chat.view'],
  ),
  'hospitality_oc': (
    role: 'oc',
    permissions: ['badge.view', 'chat.view', 'food.scan'],
  ),
  'ihl_oc': (
    role: 'oc',
    permissions: ['badge.view', 'chat.send_request', 'chat.view'],
  ),
  'admin': (
    role: 'admin',
    permissions: [
      'admin.roles',
      'badge.view',
      'chat.respond',
      'chat.view',
      'eb.tools',
      'food.scan',
      'guides.view',
    ],
  ),
};

class FakeApi extends ApiClient {
  FakeApi() : super(baseUrl: 'http://test');

  Future<http.Response> Function() handler =
      () async => http.Response('{}', 200);

  @override
  Future<http.Response> get(String path) => handler();
}

http.Response me(String profile) {
  final data = _serverProfiles[profile]!;
  return http.Response(
      jsonEncode({
        'id': 'x',
        'role': data.role,
        'permissions': data.permissions,
      }),
      200);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Capabilities> loadAs(String role) async {
    final api = FakeApi()..handler = () async => me(role);
    final caps = Capabilities(api);
    await caps.refresh();
    return caps;
  }

  test('nothing is allowed until permissions are known', () {
    final caps = Capabilities(FakeApi());
    expect(caps.loaded, isFalse);
    expect(caps.can(Perm.guidesView), isFalse);
    expect(caps.can(Perm.foodScan), isFalse);
  });

  test('delegate: guides and badge only', () async {
    final caps = await loadAs('delegate');
    expect(caps.loaded, isTrue);
    expect(caps.can(Perm.guidesView), isTrue);
    expect(caps.can(Perm.badgeView), isTrue);
    for (final p in [
      Perm.ebTools,
      Perm.foodScan,
      Perm.chatView,
      Perm.adminRoles
    ]) {
      expect(caps.can(p), isFalse, reason: p);
    }
  });

  test('eb: delegate screens plus EB tools', () async {
    final caps = await loadAs('eb');
    expect(caps.can(Perm.guidesView), isTrue);
    expect(caps.can(Perm.badgeView), isTrue);
    expect(caps.can(Perm.ebTools), isTrue);
    for (final p in [Perm.foodScan, Perm.chatView, Perm.adminRoles]) {
      expect(caps.can(p), isFalse, reason: p);
    }
  });

  test('oc without a team: badge and chat only', () async {
    final caps = await loadAs('oc');
    for (final p in [Perm.chatView, Perm.badgeView]) {
      expect(caps.can(p), isTrue, reason: p);
    }
    for (final p in [
      Perm.guidesView,
      Perm.adminRoles,
      Perm.ebTools,
      Perm.foodScan,
      Perm.chatSendRequest,
      Perm.chatRespond,
    ]) {
      expect(caps.can(p), isFalse, reason: p);
    }
    expect(caps.isAdmin, isFalse);
  });

  test('an OC role alone does not grant a permission', () async {
    final api = FakeApi()
      ..handler = () async => http.Response(
          jsonEncode({'id': 'x', 'role': 'oc', 'permissions': []}), 200);
    final caps = Capabilities(api);

    await caps.refresh();

    expect(caps.can(Perm.badgeView), isFalse);
    expect(caps.can(Perm.chatView), isFalse);
  });

  test('Hospitality OC can scan food, but cannot request or respond', () async {
    final caps = await loadAs('hospitality_oc');
    expect(caps.can(Perm.foodScan), isTrue);
    expect(caps.can(Perm.chatView), isTrue);
    expect(caps.can(Perm.chatSendRequest), isFalse);
    expect(caps.can(Perm.chatRespond), isFalse);
  });

  test('IHL OC can request a break but cannot accept or reject', () async {
    final caps = await loadAs('ihl_oc');
    expect(caps.can(Perm.chatSendRequest), isTrue);
    expect(caps.can(Perm.chatView), isTrue);
    expect(caps.can(Perm.foodScan), isFalse);
    expect(caps.can(Perm.chatRespond), isFalse);
  });

  test('admin: everything, including role changes', () async {
    final caps = await loadAs('admin');
    for (final p in _serverProfiles['admin']!.permissions) {
      expect(caps.can(p), isTrue, reason: p);
    }
    expect(caps.can(Perm.chatSendRequest), isFalse);
    expect(caps.isAdmin, isTrue);
  });

  test('permissions are saved, so an offline start still knows them', () async {
    await loadAs('delegate');

    final offline = FakeApi()..handler = () async => throw Exception('offline');
    final caps = Capabilities(offline);
    await caps.loadCached();

    expect(caps.loaded, isTrue);
    expect(caps.role, 'delegate');
    expect(caps.can(Perm.badgeView), isTrue);
    expect(caps.can(Perm.foodScan), isFalse);
  });

  test('a failed refresh keeps what was known and reports the problem',
      () async {
    final api = FakeApi()..handler = () async => me('hospitality_oc');
    final caps = Capabilities(api);
    await caps.refresh();

    api.handler = () async => http.Response('boom', 500);
    await caps.refresh();

    expect(caps.can(Perm.foodScan), isTrue);
    expect(caps.lastError, isNotNull);
  });

  test('a demotion applies on the next refresh', () async {
    final api = FakeApi()..handler = () async => me('hospitality_oc');
    final caps = Capabilities(api);
    await caps.refresh();
    expect(caps.can(Perm.foodScan), isTrue);

    api.handler = () async => me('delegate');
    await caps.refresh();
    expect(caps.can(Perm.foodScan), isFalse);
    expect(caps.can(Perm.guidesView), isTrue);
  });

  test('sign-out forgets permissions, including the saved copy', () async {
    final caps = await loadAs('admin');
    caps.clear();
    expect(caps.loaded, isFalse);
    expect(caps.can(Perm.adminRoles), isFalse);

    await Future<void>.delayed(Duration.zero);
    final fresh = Capabilities(FakeApi());
    await fresh.loadCached();
    expect(fresh.loaded, isFalse);
  });

  Widget gated(Capabilities caps, List<String> anyOf) =>
      ChangeNotifierProvider.value(
        value: caps,
        child: MaterialApp(
          home: PermissionGate(
            anyOf: anyOf,
            child: const Scaffold(body: Text('SECRET SCREEN')),
          ),
        ),
      );

  testWidgets('the gate shows the screen to a user who holds the permission',
      (tester) async {
    final caps = await loadAs('hospitality_oc');
    await tester.pumpWidget(gated(caps, [Perm.foodScan]));
    expect(find.text('SECRET SCREEN'), findsOneWidget);
  });

  testWidgets('the gate blocks a user who does not', (tester) async {
    final caps = await loadAs('delegate');
    await tester.pumpWidget(gated(caps, [Perm.foodScan]));
    expect(find.text('SECRET SCREEN'), findsNothing);
    expect(find.text('You do not have access to this screen.'), findsOneWidget);
  });

  testWidgets('the gate reacts when the role changes while it is open',
      (tester) async {
    final api = FakeApi()..handler = () async => me('hospitality_oc');
    final caps = Capabilities(api);
    await caps.refresh();
    await tester.pumpWidget(gated(caps, [Perm.foodScan]));
    expect(find.text('SECRET SCREEN'), findsOneWidget);

    api.handler = () async => me('delegate');
    await caps.refresh();
    await tester.pump();
    expect(find.text('SECRET SCREEN'), findsNothing);
  });
}
