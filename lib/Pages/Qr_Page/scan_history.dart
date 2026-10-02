import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:delego/api/scan_queue.dart';
import 'package:delego/Pages/Qr_Page/Qr_scanner.dart' show kMeals;

/// Unsynced scans and today's scan history, kept on this phone.
/// Lets the operator see what is still waiting and settle disputes at the
/// counter ("was this delegate already served?").
class ScanHistoryPage extends StatelessWidget {
  const ScanHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<ScanQueue>();
    final pending = queue.pending.reversed.toList();
    final today = queue.today;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scans on this phone'),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: 'Unsynced (${pending.length})'),
              Tab(text: 'Today (${today.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _UnsyncedTab(queue: queue, pending: pending),
            _list(context, today, empty: 'No scans yet today.'),
          ],
        ),
      ),
    );
  }
}

class _UnsyncedTab extends StatelessWidget {
  const _UnsyncedTab({required this.queue, required this.pending});
  final ScanQueue queue;
  final List<ScanRecord> pending;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (queue.blockedReason != null)
          _Note(queue.blockedReason!, Theme.of(context).colorScheme.error),
        if (pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: queue.syncing ? null : queue.flush,
                icon: const Icon(Icons.sync),
                label: Text(queue.syncing ? 'Syncing…' : 'Sync now'),
              ),
            ),
          ),
        Expanded(
          child: _list(context, pending,
              empty: 'Everything is synced.'),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.12),
        padding: const EdgeInsets.all(12),
        child: Text(text, style: TextStyle(color: color)),
      );
}

Widget _list(BuildContext context, List<ScanRecord> items,
    {required String empty}) {
  if (items.isEmpty) return Center(child: Text(empty));
  return ListView.separated(
    itemCount: items.length,
    separatorBuilder: (_, __) => const Divider(height: 1),
    itemBuilder: (_, i) => _RecordTile(items[i]),
  );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.r);
  final ScanRecord r;

  String get _meal => kMeals
      .firstWhere((m) => m.value == r.meal,
          orElse: () => (value: r.meal, label: r.meal))
      .label;

  String get _time {
    final t = r.at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (r.state) {
      ScanState.served => (Icons.check_circle, Colors.green.shade700, 'Served'),
      ScanState.pending => (Icons.cloud_off, Colors.blue.shade700, 'Waiting'),
      ScanState.duplicate => (Icons.block, Colors.red.shade700, 'Duplicate'),
      ScanState.rejected =>
        (Icons.warning_amber_rounded, Colors.orange.shade800, 'Rejected'),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(r.name ?? r.delegateId),
      subtitle: Text([
        if (r.name != null) 'ID ${r.delegateId}',
        '$_meal · ${r.diet.toUpperCase()}',
        if (r.error != null) r.error!,
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          Text(_time),
        ],
      ),
    );
  }
}
