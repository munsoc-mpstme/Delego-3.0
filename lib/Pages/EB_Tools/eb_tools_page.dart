import 'package:flutter/material.dart';
import 'dart:async';

class EBToolsPage extends StatefulWidget {
  const EBToolsPage({super.key});

  @override
  State<EBToolsPage> createState() => _EBToolsPageState();
}

class _EBToolsPageState extends State<EBToolsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- GSL State ---
  final List<String> _gslList = [];
  final TextEditingController _countryController = TextEditingController();

  // --- Timer State ---
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _countryController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // --- GSL Functions ---
  void _addCountry() {
    final country = _countryController.text.trim();
    if (country.isNotEmpty) {
      setState(() {
        _gslList.add(country);
        _countryController.clear();
      });
    }
  }

  void _removeCountry(int index) {
    setState(() {
      _gslList.removeAt(index);
    });
  }

  // --- Timer Functions ---
  void _startTimer() {
    if (_remainingSeconds > 0 && !_isRunning) {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingSeconds > 0) {
          setState(() => _remainingSeconds--);
        } else {
          _stopTimer();
        }
      });
    }
  }

  void _stopTimer() {
    setState(() => _isRunning = false);
    _timer?.cancel();
  }

  void _setTimer(int seconds) {
    _stopTimer();
    setState(() {
      _remainingSeconds = seconds;
    });
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("EB Tools"),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        bottom: TabBar(
          controller: _tabController,
          labelColor: scheme.onPrimary,
          unselectedLabelColor: scheme.onPrimary.withOpacity(0.5),
          indicatorColor: scheme.onPrimary,
          tabs: const [
            Tab(text: "GSL Manager", icon: Icon(Icons.format_list_numbered)),
            Tab(text: "Session Timer", icon: Icon(Icons.timer)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGSLTab(scheme),
          _buildTimerTab(scheme),
        ],
      ),
    );
  }

  Widget _buildGSLTab(ColorScheme scheme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _countryController,
                  decoration: const InputDecoration(
                    labelText: "Add Country",
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addCountry(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addCountry,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: const Icon(Icons.add),
              )
            ],
          ),
        ),
        Expanded(
          child: _gslList.isEmpty
              ? const Center(child: Text("GSL is empty"))
              : ReorderableListView.builder(
                  itemCount: _gslList.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final String item = _gslList.removeAt(oldIndex);
                      _gslList.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    return Card(
                      key: ValueKey('${_gslList[index]}_$index'),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          child: Text('${index + 1}', style: TextStyle(color: scheme.onPrimaryContainer)),
                        ),
                        title: Text(_gslList[index], style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeCountry(index),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTimerTab(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatTime(_remainingSeconds),
            style: TextStyle(
              fontSize: 80,
              fontWeight: FontWeight.bold,
              color: _remainingSeconds <= 10 && _remainingSeconds > 0 
                  ? scheme.error 
                  : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FloatingActionButton(
                heroTag: "timer_play",
                onPressed: _isRunning ? _stopTimer : _startTimer,
                backgroundColor: _isRunning ? scheme.error : scheme.primary,
                child: Icon(_isRunning ? Icons.pause : Icons.play_arrow, color: _isRunning ? scheme.onError : scheme.onPrimary),
              ),
              const SizedBox(width: 24),
              FloatingActionButton(
                heroTag: "timer_reset",
                onPressed: () => _setTimer(0),
                backgroundColor: scheme.secondary,
                child: Icon(Icons.stop, color: scheme.onSecondary),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const Text("Quick Presets", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildPresetButton("60s (Speech)", 60, scheme),
              _buildPresetButton("90s (Speech)", 90, scheme),
              _buildPresetButton("10m (Caucus)", 600, scheme),
              _buildPresetButton("15m (Caucus)", 900, scheme),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, int seconds, ColorScheme scheme) {
    return ActionChip(
      label: Text(label),
      backgroundColor: scheme.surfaceContainerHighest,
      onPressed: () => _setTimer(seconds),
    );
  }
}
