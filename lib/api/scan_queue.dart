import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Where a scan stands. `pending` = saved on this phone, not yet on the server.
enum ScanState { served, pending, duplicate, rejected }

/// What the operator is told right after a scan.
enum ScanKind { served, duplicate, queued, rejected, denied }

class ScanOutcome {
  const ScanOutcome(
    this.kind,
    this.message, {
    this.name,
    this.diet,
    this.localDuplicate = false,
  });

  final ScanKind kind;
  final String message;
  final String? name; // shown only if the backend returns it
  final String? diet;

  /// True when this phone (not the server) spotted the duplicate.
  final bool localDuplicate;
}

/// One scan, kept on the phone. Pending ones form the upload queue; the rest
/// are the day's history and the local duplicate check.
class ScanRecord {
  ScanRecord({
    required this.id,
    required this.delegateId,
    required this.meal,
    required this.diet,
    required this.at,
    required this.state,
    this.name,
    this.error,
  });

  final String id;
  final String delegateId;
  final String meal;
  final String diet;
  final DateTime at; // UTC
  ScanState state;
  String? name;
  String? error;

  Map<String, dynamic> toJson() => {
        'id': id,
        'delegate_id': delegateId,
        'meal': meal,
        'diet': diet,
        'at': at.toUtc().toIso8601String(),
        'state': state.name,
        if (name != null) 'name': name,
        if (error != null) 'error': error,
      };

  static ScanRecord? fromJson(dynamic j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final id = j['id']?.toString();
    final delegate = j['delegate_id']?.toString();
    if (at == null || id == null || delegate == null) return null;
    return ScanRecord(
      id: id,
      delegateId: delegate,
      meal: '${j['meal']}',
      diet: '${j['diet']}',
      at: at.toUtc(),
      state: ScanState.values.asNameMap()['${j['state']}'] ?? ScanState.pending,
      name: j['name']?.toString(),
      error: j['error']?.toString(),
    );
  }
}

enum _Result { served, duplicate, rejected, denied, retry }

class _Attempt {
  const _Attempt(this.result, this.message, {this.name, this.diet});
  final _Result result;
  final String message;
  final String? name;
  final String? diet;
}

/// Sends meal scans, and keeps them on the phone when the network is down.
///
/// Persisted in SharedPreferences, so it survives an app restart. Flushes in
/// order when connectivity returns, every [retryEvery], and on [flush].
class ScanQueue extends ChangeNotifier {
  ScanQueue(
    this._api, {
    Stream<List<ConnectivityResult>>? connectivity,
    this.timeout = const Duration(seconds: 8),
    this.retryEvery = const Duration(seconds: 15),
    DateTime Function()? clock,
  })  : _connectivity = connectivity,
        _clock = clock ?? DateTime.now;

  static const _prefsKey = 'scan_records_v1';
  static const _keepHistory = Duration(days: 3);
  static const _maxHistory = 1000;

  final ApiClient _api;
  final Stream<List<ConnectivityResult>>? _connectivity;
  final Duration timeout;
  final Duration retryEvery;
  final DateTime Function() _clock;

  final List<ScanRecord> _records = [];
  final _rejections = StreamController<String>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;
  bool _loaded = false;
  bool _flushing = false;
  bool _hasNetwork = true;
  bool _lastFailed = false;
  String? _blocked;
  int _seq = 0;

  // ----------------------------------------------------------------- state

  /// Saved scans waiting to be sent, oldest first.
  List<ScanRecord> get pending =>
      _records.where((r) => r.state == ScanState.pending).toList();

  int get pendingCount =>
      _records.where((r) => r.state == ScanState.pending).length;

  /// Waiting scans for one meal (optionally one diet). Drives the count tiles.
  int pendingFor(String meal, {String? diet}) => _records
      .where((r) =>
          r.state == ScanState.pending &&
          r.meal == meal &&
          (diet == null || r.diet == diet))
      .length;

  /// Every scan from today (this phone's local day), newest first.
  List<ScanRecord> get today {
    final now = _clock().toLocal();
    return _records.where((r) => _sameDay(r.at.toLocal(), now)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  bool get syncing => _flushing;
  bool get offline => !_hasNetwork || _lastFailed;

  /// Set when syncing stopped because of access (401/403), not the network.
  String? get blockedReason => _blocked;

  /// Messages for saved scans the server turned down (e.g. invalid QR).
  Stream<String> get rejections => _rejections.stream;

  // ------------------------------------------------------------- lifecycle

  Future<void> start() async {
    await _load();
    final stream = _connectivity ?? Connectivity().onConnectivityChanged;
    _connSub = stream.listen((results) {
      final up = results.any((r) => r != ConnectivityResult.none);
      _hasNetwork = up;
      notifyListeners();
      if (up) flush();
    });
    _timer = Timer.periodic(retryEvery, (_) => flush());
    flush();
  }

  bool _disposed = false;

  // A flush can still be in flight when the queue is disposed.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    _timer?.cancel();
    _rejections.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw != null) {
        _records.addAll((jsonDecode(raw) as List)
            .map(ScanRecord.fromJson)
            .whereType<ScanRecord>());
      }
    } catch (e) {
      debugPrint('ScanQueue load failed: $e');
    }
    _prune();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_records.map((r) => r.toJson()).toList()));
    } catch (e) {
      debugPrint('ScanQueue save failed: $e');
    }
  }

  /// Old finished scans fall off; pending ones are never dropped.
  void _prune() {
    final cutoff = _clock().toUtc().subtract(_keepHistory);
    _records.removeWhere(
        (r) => r.state != ScanState.pending && r.at.isBefore(cutoff));
    final done = _records.where((r) => r.state != ScanState.pending).toList();
    if (done.length > _maxHistory) {
      final drop = done.take(done.length - _maxHistory).toSet();
      _records.removeWhere(drop.contains);
    }
  }

  /// Forget everything (e.g. the account was deleted).
  Future<void> clearAll() async {
    _records.clear();
    _blocked = null;
    await _save();
    notifyListeners();
  }

  // -------------------------------------------------------------- scanning

  /// Sends one scan now; saves it for later if the network is the problem.
  Future<ScanOutcome> post({
    required String delegateId,
    required String meal,
    required String diet,
  }) async {
    await _load();
    final now = _clock().toUtc();
    final rec = ScanRecord(
      id: '${now.microsecondsSinceEpoch}-${_seq++}',
      delegateId: delegateId,
      meal: meal,
      diet: diet,
      at: now,
      state: ScanState.pending,
    );

    // With no connection at all, skip the 8s wait.
    final a = _hasNetwork ? await _attempt(rec) : _retry;

    switch (a.result) {
      case _Result.served:
        _lastFailed = false;
        rec
          ..state = ScanState.served
          ..name = a.name;
        await _add(rec);
        return ScanOutcome(ScanKind.served, a.message,
            name: a.name, diet: a.diet);
      case _Result.duplicate:
        _lastFailed = false;
        rec
          ..state = ScanState.duplicate
          ..name = a.name;
        await _add(rec);
        return ScanOutcome(ScanKind.duplicate, a.message,
            name: a.name, diet: a.diet);
      case _Result.rejected:
        _lastFailed = false;
        notifyListeners();
        return ScanOutcome(ScanKind.rejected, a.message);
      case _Result.denied:
        return ScanOutcome(ScanKind.denied, a.message);
      case _Result.retry:
        _lastFailed = true;
        // Offline: this phone's own record is the only duplicate check.
        if (_alreadyScannedToday(delegateId, meal)) {
          notifyListeners();
          return const ScanOutcome(ScanKind.duplicate, 'ALREADY SCANNED',
              localDuplicate: true);
        }
        await _add(rec);
        return const ScanOutcome(ScanKind.queued, 'SAVED');
    }
  }

  static const _retry = _Attempt(_Result.retry, 'offline');

  bool _alreadyScannedToday(String delegateId, String meal) {
    final now = _clock().toLocal();
    return _records.any((r) =>
        r.delegateId == delegateId &&
        r.meal == meal &&
        (r.state == ScanState.served || r.state == ScanState.pending) &&
        _sameDay(r.at.toLocal(), now));
  }

  Future<void> _add(ScanRecord r) async {
    _records.add(r);
    _prune();
    notifyListeners();
    await _save();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ------------------------------------------------------------------ sync

  /// Sends saved scans in order. Stops at the first network or access problem.
  Future<void> flush() async {
    if (_flushing || !_loaded) return;
    if (pendingCount == 0) {
      if (_blocked != null) {
        _blocked = null;
        notifyListeners();
      }
      return;
    }

    _flushing = true;
    notifyListeners();
    try {
      // Without a token every request would 401 and bounce to the login page.
      final token = await _api.token;
      if (token == null || token.isEmpty) {
        _blocked = 'Sign in to sync your saved scans.';
        return;
      }

      for (final r in pending) {
        final a = await _attempt(r);
        switch (a.result) {
          case _Result.served:
          case _Result.duplicate:
            // Duplicate = the server already has this plate: nothing to resend.
            _lastFailed = false;
            _blocked = null;
            r
              ..state = ScanState.served
              ..name ??= a.name;
          case _Result.rejected:
            _lastFailed = false;
            _blocked = null;
            r
              ..state = ScanState.rejected
              ..error = a.message;
            _rejections.add('Scan for ${r.delegateId} was rejected: ${a.message}');
          case _Result.denied:
            _blocked = a.message;
            return;
          case _Result.retry:
            _lastFailed = true;
            return;
        }
        await _save();
        notifyListeners();
      }
    } finally {
      _flushing = false;
      await _save();
      notifyListeners();
    }
  }

  Future<_Attempt> _attempt(ScanRecord r) async {
    try {
      // Form-encoded, not JSON. The server derives the day from event dates;
      // `diet` and `scanned_at` are ignored until the backend supports them.
      final res = await _api.postForm('/food/scans', {
        'delegate_id': r.delegateId,
        'meal': r.meal,
        'diet': r.diet,
        'scanned_at': r.at.toUtc().toIso8601String(),
      }).timeout(timeout);

      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      final code = res.statusCode;
      final detail = body['detail']?.toString(); // FastAPI puts the reason here

      if (code >= 200 && code < 300) {
        final name = body['name']?.toString();
        final diet = (body['food_preference'] ?? body['diet'])?.toString();
        switch (body['result']) {
          case 'served':
            return _Attempt(
                _Result.served, 'SERVED · ${r.diet.toUpperCase()}',
                name: name, diet: diet);
          case 'duplicate':
            return _Attempt(_Result.duplicate, 'ALREADY SERVED',
                name: name, diet: diet);
          default:
            return const _Attempt(_Result.rejected, 'Unexpected response');
        }
      }
      if (code == 404) {
        return _Attempt(_Result.rejected, detail ?? 'Delegate not found');
      }
      if (code == 422) {
        return _Attempt(_Result.rejected, detail ?? 'Invalid QR code or meal');
      }
      if (code >= 500 || code == 408 || code == 429) return _retry;
      return _Attempt(_Result.rejected,
          detail ?? 'Scan failed ($code). Check the event dates are set.');
    } on Forbidden {
      return const _Attempt(_Result.denied, 'You no longer have scan access');
    } on SessionExpired {
      return const _Attempt(_Result.denied, 'Session expired. Log in again.');
    } catch (_) {
      return _retry; // offline, DNS failure, timeout...
    }
  }
}
