import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import 'blocker.dart';
import 'page_card.dart';
import 'detect_consent.dart';
import 'habits.dart';
import 'hold_gate.dart';

/// Blocker → Reel limits → Scroll guard: a most-swipes-a-day and a most-swipes-in-a-row limit for short-video feeds (past either, the
/// app is closed and the phone goes home). Swipes are counted only on the
/// short-video screens of Instagram, YouTube, Snapchat and TikTok. Sits at the bottom of the Reel limits page.
class ScrollGuardSection extends StatefulWidget {
  final AppServices services;
  const ScrollGuardSection(this.services, {super.key});

  @override
  State<ScrollGuardSection> createState() => _ScrollGuardSectionState();
}

class _ScrollGuardSectionState extends State<ScrollGuardSection> {
  final _bridge = ScrollBridge();
  ScrollState? _st;
  var _day = 0, _run = 0, _quiet = 30, _pause = 5;
  var _dirty = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(keepDraft: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool keepDraft = false}) async {
    final st = await _bridge.state();
    if (!mounted) return;
    setState(() {
      _st = st;
      if (keepDraft && _dirty) return;
      final r = st.rule ?? const ScrollRule();
      _day = r.maxPerDay;
      _run = r.runSwipes;
      _quiet = r.quietSec;
      _pause = r.pauseMinutes;
    });
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  ScrollRule get _draft => ScrollRule(maxPerDay: _day, runSwipes: _run, quietSec: _quiet, pauseMinutes: _pause);

  Future<void> _save() async {
    final before = _st?.rule;
    final next = _draft;
    if (next.on) {
      final bridge = BlockerBridge();
      if (!await bridge.consent()) {
        if (!mounted || !await askDetectionConsent(context)) return _say('The scroll guard needs your OK to see when a short-video feed is on screen.');
        await bridge.setConsent(true);
      }
    }
    if (before != null && before.on && !next.noLooserThan(before)) {
      if (!mounted) return;
      final ok = await askHold(
        context,
        title: next.on ? 'Loosen the scroll guard' : 'Turn off the scroll guard',
        intro: 'To loosen or turn off the scroll guard, press and hold a finger on the screen for 30 seconds. '
            'Nothing is stored or sent.',
      );
      if (!ok) return;
    }
    final r = await _bridge.save(next);
    if (r != 'ok') return _say('That rule is not valid.');
    _dirty = false;
    await _load();
    _say(next.on ? 'Scroll guard saved.' : 'Scroll guard is off.');
  }

  Widget _stepper(String label, int value, int step, int min, int max, void Function(int) set, {String zero = 'Off', String unit = ''}) {
    return Row(children: [
      Expanded(child: Text(label)),
      IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: value <= min ? null : () => setState(() { set((value - step).clamp(min, max)); _dirty = true; }),
      ),
      SizedBox(width: 64, child: Text(value == 0 ? zero : '$value$unit', textAlign: TextAlign.center)),
      IconButton(
        icon: const Icon(Icons.add_circle_outline),
        onPressed: value >= max ? null : () => setState(() { set((value + step).clamp(min, max)); _dirty = true; }),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    if (st == null) return const SizedBox();
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageCard(
        icon: Icons.swipe_vertical_rounded,
        title: 'Scroll guard',
        subtitle: 'Watches how you swipe through short videos (Instagram Reels, YouTube Shorts, Snapchat Spotlight, TikTok). '
            'When the same scrolling keeps going past your limit, the app is closed and you land on the home screen. '
            'Only the number of swipes is kept on this phone, never what you scrolled past.',
        children: [
          Text('Swipes today: ${st.swipesToday}', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          _stepper('Most swipes a day', _day, 20, 0, 5000, (v) => _day = v),
          _stepper('Most swipes in a row', _run, 5, 0, 500, (v) => _run = v),
          if (_run > 0) ...[
            _stepper('A run ends after a quiet of', _quiet, 5, 5, 300, (v) => _quiet = v, unit: ' s'),
            _stepper('Then stay closed for', _pause, 1, 1, 120, (v) => _pause = v, unit: ' min'),
          ],
          const SizedBox(height: 8),
          Text('Turning a part up or off later takes a 30 second press-and-hold, like the other limits. Making it stricter is free.', style: t.textTheme.bodySmall),
          if (_dirty) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: Text(_draft.on ? 'Save the scroll guard' : 'Turn the scroll guard off')),
          ],
        ],
      ),
    ]);
  }
}
