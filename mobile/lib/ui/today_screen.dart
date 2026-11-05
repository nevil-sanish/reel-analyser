import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../native/counter_bridge.dart';
import 'debug_screen.dart';
import 'setup_screen.dart';

class TodayScreen extends StatefulWidget {
  final AppServices services;
  const TodayScreen(this.services, {super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  CounterBridge get b => widget.services.bridge;
  List<DayTotal> _days = [];
  CounterStatus? _status;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final days = await b.history();
    final status = await b.status();
    if (!mounted) return;
    setState(() {
      _days = days;
      _status = status;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _days.where((d) => d.date == localDate()).firstOrNull ?? DayTotal(localDate(), const {}, 0, 0);
    final most = _days.fold(1, (m, d) => d.reels > m ? d.reels : m);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(tooltip: 'Debug', icon: const Icon(Icons.bug_report_outlined), onPressed: () => _open(DebugScreen(widget.services))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_status != null && !_status!.serviceEnabled)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.accessibility_new),
                  title: const Text('Set up counting'),
                  subtitle: const Text('Turn on Reel Bot in Accessibility so it can count the reels you watch.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(SetupScreen(widget.services)),
                ),
              ),
            if (today.detectionLooksBroken)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: const Text('Counting may be broken after an Instagram/YouTube update'),
                  trailing: TextButton(onPressed: () => _open(DebugScreen(widget.services)), child: const Text('Debug')),
                ),
              ),
            const SizedBox(height: 24),
            Center(child: Text('${today.reels}', style: theme.textTheme.displayLarge)),
            Center(child: Text('reels and shorts today · ${(today.ms / 60000).round()} min', style: theme.textTheme.titleMedium)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                Chip(label: Text('Instagram ${today.reelsByApp['instagram'] ?? 0}')),
                Chip(label: Text('YouTube ${today.reelsByApp['youtube'] ?? 0}')),
              ],
            ),
            const SizedBox(height: 24),
            Text('Last 14 days', style: theme.textTheme.titleSmall),
            for (final d in _days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 90, child: Text(d.date.substring(5))),
                    Expanded(child: LinearProgressIndicator(value: d.reels / most, minHeight: 10)),
                    SizedBox(width: 90, child: Text('${d.reels} · ${(d.ms / 60000).round()}m', textAlign: TextAlign.end)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
