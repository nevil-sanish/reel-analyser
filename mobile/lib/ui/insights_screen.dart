import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../native/counter_bridge.dart';
import 'debug_screen.dart';
import 'liquid.dart';
import '../flavor.dart';
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
    // Reel counts only exist with the optional Accessibility counter; time comes from Usage access without it.
    final counting = _status?.serviceEnabled == true || _days.any((d) => d.reels > 0);
    final total = _days.fold(0, (s, d) => s + d.reels);
    final minutes = _days.fold(0, (s, d) => s + d.timeMs) ~/ 60000;
    final active = _days.where((d) => counting ? d.reels > 0 : d.timeMs > 0).length;
    // Time spent is what matters here; fall back to counts until any watch time is recorded.
    final byTime = _hours.any((h) => h.$2 > 0);
    int weight((int, int) h) => byTime ? h.$2 : h.$1;
    final peak = _hours.indexed.reduce((a, b) => weight(b.$2) > weight(a.$2) ? b : a);
    final blocks = timeBlocks(_hours);
    int blockWeight((String, String, int, int) b) => byTime ? b.$4 : b.$3;
    final blockTotal = blocks.fold(0, (s, b) => s + blockWeight(b));
    final topBlock = blocks.indexed.reduce((a, b) => blockWeight(b.$2) > blockWeight(a.$2) ? b : a);
    final weekday = weekdayMinutes(_days);
    final topDay = weekday.indexed.reduce((a, b) => b.$2 > a.$2 ? b : a);
    String dur(int m) => m < 60 ? '${m}m' : '${m ~/ 60}h ${m % 60}m';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return LiquidScaffold(
      background: false,
      appBar: AppBar(
        title: const Text('Insights'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), // clear of the floating tab bar
          children: [
            if (_status != null && !_status!.usageAccess && !counting) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.insights_rounded),
                  title: const Text('Insights are optional'),
                  subtitle: Text(kPlayBuild
                      ? 'Allow usage access to see your time in Instagram and YouTube.'
                      : 'Allow usage access to see your time in Instagram and YouTube, '
                          'and turn on Accessibility to count reels and Shorts. Either one is enough.'),
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
                  tween: Tween(begin: 0, end: (counting ? total : minutes).toDouble()),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text(counting ? '${v.round()} reels & shorts' : '${dur(v.round())} in the apps',
                      style: t.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                ),
                const SizedBox(height: 14),
                Row(children: counting
                    ? [
                        _HeroStat(dur(minutes), _days.any((d) => d.appMs.isNotEmpty) ? 'in the apps' : 'watching'),
                        _HeroStat(active == 0 ? '0' : '${(total / active).round()}', 'per active day'),
                        _HeroStat('${today.reels}', 'today'),
                      ]
                    : [
                        _HeroStat(active == 0 ? '0m' : dur(minutes ~/ active), 'per active day'),
                        _HeroStat(dur(today.timeMs ~/ 60000), 'today'),
                      ]),
              ]),
            ),
            const SizedBox(height: 16),
            _Section(
              title: counting ? 'Reels & shorts each day' : 'Time each day',
              subtitle: active == 0 ? 'Nothing yet' : 'On $active of $_range days',
              child: _Bars(
                values: [for (final d in _days) counting ? d.reels.toDouble() : d.timeMs / 60000],
                valueLabels: [
                  for (final d in _days)
                    counting ? (d.reels == 0 ? '' : '${d.reels}') : (d.timeMs < 60000 ? '' : '${d.timeMs ~/ 60000}m'),
                ],
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
              subtitle: weight(peak.$2) == 0
                  ? 'Nothing yet'
                  : 'Most ${byTime ? 'time' : 'reels'} ${blocks[topBlock.$1].$1 == 'Night' ? 'at night' : 'in the ${blocks[topBlock.$1].$1.toLowerCase()}'}'
                      ' · peak around ${hourLabel(peak.$1)}',
              child: Column(children: [
                for (final (i, b) in blocks.indexed)
                  _BlockRow(b.$1, b.$2, b.$3, blockTotal == 0 ? 0 : blockWeight(b) / blockTotal, dur(b.$4 ~/ 60000),
                      highlight: blockWeight(b) > 0 && i == topBlock.$1),
              ]),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'By weekday',
              subtitle: active < 7 ? 'Shows once you have a week of watching' : 'You watch most on ${names[topDay.$1]}s',
              child: active < 7
                  ? const SizedBox()
                  : _Bars(
                      values: weekday,
                      valueLabels: [for (final w in weekday) w == 0 ? '' : '${w.round()}m'],
                      labels: [for (final n in names) n.substring(0, 1)],
                      highlight: topDay.$1,
                    ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Apps today',
              child: Row(children: [
                for (final (icon, app, name, unit) in [
                  (Icons.movie_rounded, 'instagram', 'Instagram', 'reels'),
                  (Icons.smart_display_rounded, 'youtube', 'YouTube', 'shorts'),
                ])
                  _AppStat(
                    icon,
                    today.appMs.isEmpty ? '${today.reelsByApp[app] ?? 0}' : dur((today.appMs[app] ?? 0) ~/ 60000),
                    counting && today.appMs.isNotEmpty ? '$name · ${today.reelsByApp[app] ?? 0} $unit' : name,
                  ),
              ]),
            ),
            // Once one part is on, offer the other quietly.
            if (_status != null && (_status!.usageAccess || counting) && !(_status!.usageAccess && counting)) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _open(SetupScreen(widget.services)),
                icon: const Icon(Icons.add_rounded),
                label: Text(counting ? 'Optional: time in each app too' : 'Optional: count reels and Shorts too'),
              ),
            ],
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

/// Reels and watch time in four parts of the day: (name, hours, reels, ms).
List<(String, String, int, int)> timeBlocks(List<(int, int)> hours) {
  (int, int) sum(int from, int to) {
    var r = 0, ms = 0;
    for (var h = from; h < to; h++) {
      r += hours[h].$1;
      ms += hours[h].$2;
    }
    return (r, ms);
  }

  final n = sum(0, 6), m = sum(6, 12), a = sum(12, 18), e = sum(18, 24);
  return [
    ('Night', '12a–6a', n.$1, n.$2),
    ('Morning', '6a–12p', m.$1, m.$2),
    ('Afternoon', '12p–6p', a.$1, a.$2),
    ('Evening', '6p–12a', e.$1, e.$2),
  ];
}

/// Average minutes per weekday, Monday first.
List<double> weekdayMinutes(List<DayTotal> days) {
  final sum = List.filled(7, 0.0), count = List.filled(7, 0);
  for (final d in days) {
    final w = DateTime.parse(d.date).weekday - 1;
    sum[w] += d.timeMs / 60000;
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

  /// Printed above each bar ("" for none).
  final List<String> valueLabels;
  final int highlight;
  const _Bars({required this.values, required this.labels, this.valueLabels = const [], this.highlight = -1});

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
                if (i < valueLabels.length && valueLabels[i].isNotEmpty)
                  Text(valueLabels[i],
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: t.colorScheme.onSurface)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: most == 0 ? 0 : values[i] / most),
                  duration: Duration(milliseconds: 500 + 15 * i),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Container(
                    height: values[i] == 0 ? 3 : 6 + 84 * v,
                    decoration: BoxDecoration(
                      gradient: i == highlight && values[i] > 0 ? Brand.gradient : null,
                      color: i == highlight && values[i] > 0
                          ? null
                          : t.colorScheme.primary.withValues(alpha: values[i] == 0 ? 0.1 : 0.35),
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
  final String value;
  final String label;
  const _AppStat(this.icon, this.value, this.label);

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
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ]),
      );
}

/// One part of the day: name, hours, a share bar, reels and minutes.
class _BlockRow extends StatelessWidget {
  final String name;
  final String hours;
  final int reels;
  final double share;
  final String time;
  final bool highlight;

  /// [share] is this block's part of the time watched (or of the reels, before any time is recorded).
  const _BlockRow(this.name, this.hours, this.reels, this.share, this.time, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(
          width: 92,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(hours, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(children: [
              Container(height: 14, color: t.colorScheme.primary.withValues(alpha: 0.1)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: highlight ? Brand.gradient : null,
                      color: highlight ? null : t.colorScheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        SizedBox(
          width: 84,
          child: Text(reels == 0 ? (share == 0 ? '—' : time) : '$reels · $time',
              textAlign: TextAlign.end, style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
