import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../native/counter_bridge.dart';
import 'debug_screen.dart';
import 'liquid.dart';
import 'setup_screen.dart';
import 'theme.dart';

/// Insights tab: how much you watch, on which days and at what time, over a week or a month.
class InsightsScreen extends StatefulWidget {
  final AppServices services;
  const InsightsScreen(this.services, {super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> with WidgetsBindingObserver {
  CounterBridge get b => widget.services.bridge;
  var _range = 7;
  List<DayTotal> _days = [];
  List<(int, int)> _hours = List.filled(24, (0, 0));
  CounterStatus? _status;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
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
    final days = await b.history(days: _range);
    final hours = await b.hourly(days: _range);
    final status = await b.status();
    if (!mounted) return;
    setState(() {
      _days = fillDays(days, _range, DateTime.now());
      _hours = hours;
      _status = status;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = _days.isEmpty ? DayTotal(localDate(), const {}, 0, 0) : _days.last;
    final total = _days.fold(0, (s, d) => s + d.reels);
    final minutes = _days.fold(0, (s, d) => s + d.ms) ~/ 60000;
    final peak = _hours.indexed.reduce((a, b) => b.$2.$1 > a.$2.$1 ? b : a);
    final weekday = weekdayMinutes(_days);
    final topDay = weekday.indexed.reduce((a, b) => b.$2 > a.$2 ? b : a);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return LiquidScaffold(
      background: false,
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          const ThemeToggle(),
          IconButton(tooltip: 'Debug', icon: const Icon(Icons.bug_report_outlined), onPressed: () => _open(DebugScreen(widget.services))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), // clear of the floating tab bar
          children: [
            if (_status != null && !_status!.serviceEnabled) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.accessibility_new),
                  title: const Text('Set up counting'),
                  subtitle: const Text('Turn on Reel Bot in Accessibility so it can count what you watch.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(SetupScreen(widget.services)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (today.detectionLooksBroken) ...[
              Card(
                color: t.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: const Text('Counting may be broken after an Instagram/YouTube update'),
                  trailing: TextButton(onPressed: () => _open(DebugScreen(widget.services)), child: const Text('Debug')),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Center(
              child: SegmentedButton<int>(
                segments: const [ButtonSegment(value: 7, label: Text('Week')), ButtonSegment(value: 30, label: Text('Month'))],
                selected: {_range},
                showSelectedIcon: false,
                onSelectionChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _range = v.first);
                  _load();
                },
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(28)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_range == 7 ? 'This week' : 'Last 30 days', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: total.toDouble()),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text('${v.round()} reels & shorts',
                      style: t.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  _HeroStat('${minutes ~/ 60}h ${minutes % 60}m', 'watching'),
                  _HeroStat('${(minutes / _range).round()}m', 'a day'),
                  _HeroStat('${today.reels}', 'today'),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Minutes each day',
              child: _Bars(
                values: [for (final d in _days) d.ms / 60000],
                labels: [
                  for (final (i, d) in _days.indexed)
                    _range == 7 ? names[DateTime.parse(d.date).weekday - 1].substring(0, 1) : (i % 5 == 4 ? d.date.substring(8) : ''),
                ],
                highlight: _days.length - 1,
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'When you watch',
              subtitle: peak.$2.$1 == 0 ? 'Nothing counted yet' : 'Most around ${hourLabel(peak.$1)}',
              child: _Bars(
                values: [for (final h in _hours) h.$1.toDouble()],
                labels: [for (var h = 0; h < 24; h++) h % 6 == 0 ? hourLabel(h) : ''],
                highlight: peak.$2.$1 == 0 ? -1 : peak.$1,
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'By weekday',
              subtitle: topDay.$2 == 0 ? 'Average minutes' : 'You watch most on ${names[topDay.$1]}s',
              child: _Bars(values: weekday, labels: [for (final n in names) n.substring(0, 1)], highlight: topDay.$2 == 0 ? -1 : topDay.$1),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Apps today',
              child: Row(children: [
                _AppStat(Icons.movie_rounded, 'Instagram', today.reelsByApp['instagram'] ?? 0),
                _AppStat(Icons.smart_display_rounded, 'YouTube', today.reelsByApp['youtube'] ?? 0),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry per day for the last [n] days ending today, oldest first; days with nothing are zeros.
List<DayTotal> fillDays(List<DayTotal> rows, int n, DateTime now) {
  final byDate = {for (final d in rows) d.date: d};
  return [
    for (var i = n - 1; i >= 0; i--)
      byDate[localDate(now.subtract(Duration(days: i)))] ?? DayTotal(localDate(now.subtract(Duration(days: i))), const {}, 0, 0),
  ];
}

/// Average minutes per weekday, Monday first.
List<double> weekdayMinutes(List<DayTotal> days) {
  final sum = List.filled(7, 0.0), count = List.filled(7, 0);
  for (final d in days) {
    final w = DateTime.parse(d.date).weekday - 1;
    sum[w] += d.ms / 60000;
    count[w]++;
  }
  return [for (var i = 0; i < 7; i++) count[i] == 0 ? 0 : sum[i] / count[i]];
}

String hourLabel(int h) => h == 0 ? '12a' : h < 12 ? '${h}a' : h == 12 ? '12p' : '${h - 12}p';

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  const _HeroStat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.textTheme.titleMedium),
          if (subtitle != null) Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          child,
        ]),
      ),
    );
  }
}

/// A small animated bar chart; [highlight] is drawn in the full gradient, the rest softer.
class _Bars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final int highlight;
  const _Bars({required this.values, required this.labels, this.highlight = -1});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final most = values.fold(0.0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 130,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: values.length > 12 ? 1 : 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: most == 0 ? 0 : values[i] / most),
                  duration: Duration(milliseconds: 500 + 15 * i),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Container(
                    height: 4 + 96 * v,
                    decoration: BoxDecoration(
                      gradient: i == highlight ? Brand.gradient : null,
                      color: i == highlight ? null : t.colorScheme.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 14,
                  child: Text(labels[i], maxLines: 1, overflow: TextOverflow.visible, softWrap: false,
                      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant, fontSize: 10)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _AppStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int n;
  const _AppStat(this.icon, this.label, this.n);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ]),
      );
}
