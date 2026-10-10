import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import 'package:delego/api/api_client.dart';
import 'package:delego/api/scan_queue.dart';
import 'package:delego/Pages/Qr_Page/scan_history.dart';
import 'package:delego/auth/capabilities.dart';

/// value = what is sent to the server, label = what the operator sees.
/// These strings are the server's meal names (POST /food/scans).
const kMeals = <({String value, String label})>[
  (value: 'breakfast', label: 'Breakfast'),
  (value: 'lunch', label: 'Lunch'),
  (value: 'high_tea', label: 'High Tea'),
];

/// Diets the operator can serve. The selected one is sent with every scan.
const kDiets = <({String value, String label})>[
  (value: 'veg', label: 'Veg'),
  (value: 'jain', label: 'Jain'),
];

enum _Outcome { served, duplicate, queued, error }

class _ScanResult {
  _ScanResult(this.outcome, this.message, {this.name, this.diet});
  final _Outcome outcome;
  final String message;
  final String? name; // shown only if the backend returns it
  final String? diet;
}

class QrScanner extends StatefulWidget {
  const QrScanner({super.key});

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> {
  final MobileScannerController controller = MobileScannerController();

  String _meal = kMeals[1].value;
  bool _busy = false; // request in flight or result on screen
  _ScanResult? _result;
  String? _lastId;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Plate counts
  Map<String, int> _counts = {};
  bool _countsLoaded = false;
  String? _diet; // must be chosen before scanning
  Timer? _poll;

  late final ScanQueue _queue;
  StreamSubscription<String>? _rejectSub;
  int _lastPending = 0;

  @override
  void initState() {
    super.initState();
    _queue = context.read<ScanQueue>();
    _lastPending = _queue.pendingCount;
    _queue.addListener(_onQueueChanged);
    // A saved scan the server turned down: tell the operator once.
    _rejectSub = _queue.rejections.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    });
    _loadCounts();
    // The counts come from the server and cover every phone scanning, so refresh
    // often: a scan made on another phone shows up here within a few seconds.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _loadCounts());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _queue.removeListener(_onQueueChanged);
    _rejectSub?.cancel();
    controller.dispose();
    super.dispose();
  }

  // Saved scans just reached the server: pull the fresh counts.
  void _onQueueChanged() {
    final now = _queue.pendingCount;
    if (now < _lastPending) _loadCounts();
    _lastPending = now;
  }

  // ---------------------------------------------------------------- counts

  Future<void> _loadCounts() async {
    if (!mounted) return;
    final meal = _meal;
    try {
      final res = await context
          .read<ApiClient>()
          .get('/food/plate_count?meal=$meal');
      if (res.statusCode != 200) return;
      if (!_countsLoaded) debugPrint('PLATES $meal: ${res.body}');

      final parsed = _parseCounts(jsonDecode(res.body));
      if (!mounted || meal != _meal) return; // meal changed meanwhile
      setState(() {
        _counts = parsed;
        _countsLoaded = true;
      });
    } catch (_) {
      // Keep the last known counts; scanning must never depend on this.
    }
  }

  /// The response shape is not documented, so accept the common ones:
  ///   {"veg": 5, "non_veg": 3, "jain": 1, "total": 9}
  ///   {"by_diet": {...}, "total": 9}   (also counts / diets / breakdown)
  ///   [{"diet": "veg", "count": 5}, ...]
  /// Check the real shape in /docs and simplify.
  Map<String, int> _parseCounts(dynamic body) {
    String norm(String k) => k
        .toLowerCase()
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .replaceAll('nonveg', 'non_veg');
    int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    final out = <String, int>{};

    void fromMap(Map m) {
      m.forEach((k, v) {
        if (v is num) out[norm('$k')] = v.toInt();
      });
    }

    void fromList(List l) {
      for (final e in l) {
        if (e is Map) {
          final diet = e['diet'] ?? e['food_preference'];
          final count = e['count'] ?? e['plates'] ?? e['total'];
          if (diet != null) out[norm('$diet')] = toInt(count);
        }
      }
    }

    if (body is Map) {
      final nested = body['by_diet'] ??
          body['counts'] ??
          body['diets'] ??
          body['breakdown'];
      if (nested is Map) {
        fromMap(nested);
        if (body['total'] is num) out['total'] = (body['total'] as num).toInt();
      } else if (nested is List) {
        fromList(nested);
        if (body['total'] is num) out['total'] = (body['total'] as num).toInt();
      } else {
        fromMap(body);
      }
    } else if (body is List) {
      fromList(body);
    }

    out.putIfAbsent('total', () => _sumDiets(out));
    return out;
  }

  // Fallback total when the server doesn't send one: every diet it reported.
  int _sumDiets(Map<String, int> m) => m.entries
      .where((e) => e.key != 'total')
      .fold(0, (sum, e) => sum + e.value);

  // Server count + scans still saved on this phone, so numbers keep moving offline.
  int _countFor(String diet) => diet == 'all'
      ? (_counts['total'] ?? _sumDiets(_counts)) + _queue.pendingFor(_meal)
      : (_counts[diet] ?? 0) + _queue.pendingFor(_meal, diet: diet);

  String _fmt(String diet) => _countsLoaded ? '${_countFor(diet)}' : '–';

  String get _mealLabel => kMeals.firstWhere((m) => m.value == _meal).label;

  Widget _countTile(
    TextTheme text,
    ColorScheme scheme, {
    required String label,
    required String value,
    bool selected = false,
    VoidCallback? onTap, // null = display only (Total)
  }) {
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: text.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: fg),
              ),
              Text(label, style: text.labelLarge?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countsPanel(ColorScheme scheme, TextTheme text) {
    final selectedLabel = _diet == null
        ? null
        : kDiets.firstWhere((d) => d.value == _diet).label;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _countTile(text, scheme, label: 'Total', value: _fmt('all')),
              for (final d in kDiets) ...[
                const SizedBox(width: 8),
                _countTile(
                  text,
                  scheme,
                  label: d.label,
                  value: _fmt(d.value),
                  selected: _diet == d.value,
                  onTap: () => setState(() => _diet = d.value),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selectedLabel == null
                ? 'Select Veg or Jain to start scanning'
                : 'Scanning $_mealLabel · $selectedLabel plates',
            style: text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: selectedLabel == null ? scheme.error : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Live count across all scanners · updates every few seconds',
            style: text.bodySmall
                ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- scans

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _diet == null) return;

    String? id;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        id = v;
        break;
      }
    }
    if (id == null) return;

    // Ignore the same code re-detected within 3s (camera fires repeatedly).
    final now = DateTime.now();
    if (id == _lastId && now.difference(_lastAt).inSeconds < 3) return;
    _lastId = id;
    _lastAt = now;

    setState(() => _busy = true);
    final result = await _submit(id);
    if (!mounted) return;

    HapticFeedback.heavyImpact();
    if (result.outcome != _Outcome.served) {
      HapticFeedback.vibrate();
    }
    setState(() => _result = result);

    // Update the plate counts right after a successful scan.
    if (result.outcome == _Outcome.served) _loadCounts();

    // Auto-dismiss so the queue keeps moving; tap also dismisses.
    await Future.delayed(const Duration(seconds: 2));
    _dismiss();
  }

  void _dismiss() {
    if (!mounted || _result == null) return;
    setState(() {
      _result = null;
      _busy = false;
    });
  }

  Future<_ScanResult> _submit(String delegateId) async {
    final o = await _queue.post(
      delegateId: delegateId,
      meal: _meal,
      diet: _diet!,
    );
    return switch (o.kind) {
      ScanKind.served =>
        _ScanResult(_Outcome.served, o.message, name: o.name, diet: o.diet),
      ScanKind.duplicate => _ScanResult(_Outcome.duplicate, o.message,
          name: o.name, diet: o.diet),
      ScanKind.queued => _ScanResult(_Outcome.queued, o.message,
          name: null, diet: _diet),
      ScanKind.rejected || ScanKind.denied =>
        _ScanResult(_Outcome.error, o.message),
    };
  }

  Color _colorFor(_Outcome o) => switch (o) {
        _Outcome.served => Colors.green.shade700,
        _Outcome.duplicate => Colors.red.shade700,
        _Outcome.queued => Colors.blue.shade700,
        _Outcome.error => Colors.orange.shade800,
      };

  IconData _iconFor(_Outcome o) => switch (o) {
        _Outcome.served => Icons.check_circle,
        _Outcome.duplicate => Icons.block,
        _Outcome.queued => Icons.cloud_upload_outlined,
        _Outcome.error => Icons.warning_amber_rounded,
      };

  Widget _banner(ScanQueue q, ColorScheme scheme) {
    final n = q.pendingCount;
    String? text;
    Color color = Colors.blue.shade700;
    if (q.blockedReason != null && n > 0) {
      text = '${q.blockedReason} $n ${n == 1 ? 'scan is' : 'scans are'} kept saved.';
      color = scheme.error;
    } else if (q.syncing && n > 0) {
      text = 'Syncing $n ${n == 1 ? 'scan' : 'scans'}';
    } else if (q.offline) {
      text = n > 0
          ? 'Offline · $n ${n == 1 ? 'scan' : 'scans'} saved, will sync automatically'
          : 'Offline · scans will be saved and sync automatically';
      color = Colors.orange.shade800;
    } else if (n > 0) {
      text = '$n ${n == 1 ? 'scan' : 'scans'} waiting to sync';
    }
    if (text == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          if (n > 0 && !q.syncing)
            TextButton(
              onPressed: q.flush,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Sync now'),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final caps = context.watch<Capabilities>();
    final queue = context.watch<ScanQueue>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // The server enforces this too; this just avoids a dead screen.
    if (!caps.can(Perm.foodScan)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Meal Scanner'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You do not have access to meal scanning.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Scanner'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Unsynced scans and history',
            icon: Badge(
              isLabelVisible: queue.pendingCount > 0,
              label: Text('${queue.pendingCount}'),
              child: const Icon(Icons.history),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScanHistoryPage()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _banner(queue, scheme),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<String>(
                  segments: [
                    for (final m in kMeals)
                      ButtonSegment(value: m.value, label: Text(m.label)),
                  ],
                  selected: {_meal},
                  onSelectionChanged: (s) {
                    setState(() {
                      _meal = s.first;
                      _countsLoaded = false; // don't show the old meal's numbers
                      _counts = {};
                    });
                    _loadCounts();
                  },
                ),
              ),
              _countsPanel(scheme, text),
              Expanded(
                child: MobileScanner(
                  controller: controller,
                  onDetect: _onDetect,
                ),
              ),
            ],
          ),
          if (_result != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: _dismiss,
                child: Container(
                  color: _colorFor(_result!.outcome),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(_result!.outcome),
                          size: 96, color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        _result!.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_result!.name != null) ...[
                        const SizedBox(height: 12),
                        Text(_result!.name!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 22)),
                      ],
                      if (_result!.diet != null) ...[
                        const SizedBox(height: 4),
                        Text(_result!.diet!.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 18)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.toggleTorch,
        child: const Icon(Icons.flash_on),
      ),
    );
  }
}