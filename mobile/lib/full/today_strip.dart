import 'package:flutter/material.dart';

import '../app_services.dart';
import '../ui/liquid.dart';
import 'full_bridge.dart';

/// The strip under the Ask heading: today's reels, shorts and time in the apps. Shown only when Usage access or the counter is on;
/// it reads its own numbers from the counter, so the shared Ask screen knows nothing about them.
class TodayStrip extends StatefulWidget {
  final AppServices services;
  final VoidCallback onTap;
  const TodayStrip(this.services, {required this.onTap, super.key});

  @override
  State<TodayStrip> createState() => _TodayStripState();
}

class _TodayStripState extends State<TodayStrip> with WidgetsBindingObserver {
  final _bridge = FullBridge();
  DayTotal? _today;
  var _counting = false;
  var _usage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    DayTotal? today;
    var counting = false, usage = false;
    try {
      today = (await _bridge.history(days: 1)).where((d) => d.date == localDate()).firstOrNull;
      final st = await _bridge.status();
      counting = st.serviceEnabled;
      usage = st.usageAccess;
    } on Exception {
      today = null;
    }
    if (!mounted) return;
    setState(() {
      _today = today;
      _counting = counting || (today?.reels ?? 0) > 0;
      _usage = usage;
    });
  }

  @override
  Widget build(BuildContext context) =>
      // Insights are optional: with neither Usage access nor the counter there's nothing to show.
      _counting || _usage ? _StripBody(_today, counting: _counting, onTap: widget.onTap) : const SizedBox.shrink();
}

/// Today at a glance on the Ask tab; tap for Insights.
class _StripBody extends StatelessWidget {
  final DayTotal? today;

  /// With the optional reel counter on, the strip leads with counts; without it, with time in each app.
  final bool counting;
  final VoidCallback? onTap;
  const _StripBody(this.today, {this.counting = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = today ?? DayTotal(localDate(), const {}, 0, 0);
    String min(int ms) => ms < 3600000 ? '${ms ~/ 60000}m' : '${ms ~/ 3600000}h ${ms % 3600000 ~/ 60000}m';
    Widget stat(String v, String label) => Expanded(
          child: Column(children: [
            Text(v, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        );
    return GestureDetector(
      onTap: onTap,
      child: Glass(
        radius: 24,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(children: [
          if (counting) ...[
            stat('${d.reelsByApp['instagram'] ?? 0}', 'Reels today'),
            stat('${d.reelsByApp['youtube'] ?? 0}', 'Shorts today'),
            stat(min(d.timeMs), d.appMs.isEmpty ? 'Watching' : 'In the apps'),
          ] else ...[
            stat(min(d.appMs['instagram'] ?? 0), 'Instagram today'),
            stat(min(d.appMs['youtube'] ?? 0), 'YouTube today'),
          ],
          Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

