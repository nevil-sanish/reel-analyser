import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import 'blocker.dart';
import 'detect_consent.dart';
import 'full_bridge.dart';
import 'habits.dart';
import 'paragraph_gate.dart';

/// Blocker → Scroll: a most-swipes-a-day and a "too many swipes too fast" pause for short-video feeds, and the user's own habits
/// worked out on the phone. Swipes are counted only on the short-video screens of Instagram, YouTube, Snapchat and TikTok.
class ScrollScreen extends StatefulWidget {
  final AppServices services;
  const ScrollScreen(this.services, {super.key});

  @override
  State<ScrollScreen> createState() => _ScrollScreenState();
}

class _ScrollScreenState extends State<ScrollScreen> {
  final _bridge = ScrollBridge();
  ScrollState? _st;
  Habits? _habits;
  var _day = 0, _burst = 0, _window = 10, _pause = 5;
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
    final full = FullBridge();
    Habits? h;
    try {
      final hourly = await full.hourly(days: 14);
      final days = await full.history(days: 14);
      h = Habits.analyse([for (final e in hourly) e.$2], [for (final d in days) d.reels]);
    } on Object {
      h = null;
    }
    if (!mounted) return;
    setState(() {
      _st = st;
      _habits = h;
      if (keepDraft && _dirty) return;
      final r = st.rule ?? const ScrollRule();
      _day = r.maxPerDay;
      _burst = r.burstSwipes;
      _window = r.burstMinutes;
      _pause = r.pauseMinutes;
    });
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  ScrollRule get _draft => ScrollRule(maxPerDay: _day, burstSwipes: _burst, burstMinutes: _window, pauseMinutes: _pause);

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
      final ok = await askParagraph(
        context,
        title: next.on ? 'Loosen the scroll guard' : 'Turn off the scroll guard',
        intro: 'To loosen or turn off the scroll guard, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
            'Pasting is not accepted. It is checked on your phone only and is not stored.',
        action: next.on ? 'Save the change' : 'Turn it off',
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

  Widget _card(List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
      );

  @override
  Widget build(BuildContext context) {
    final st = _st;
    if (st == null) return const SizedBox();
    final t = Theme.of(context);
    final h = _habits;
    final notes = h?.notes() ?? const <String>[];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
      _card([
        Text('Scroll guard', style: t.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Counts swipes through short videos (Instagram Reels, YouTube Shorts, Snapchat Spotlight, TikTok) and stops you when you pass the limits you set. '
          'Only the number of swipes is kept on this phone, never what you scrolled past.',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text('Swipes today: ${st.swipesToday}', style: t.textTheme.titleMedium),
      ]),
      _card([
        _stepper('Most swipes a day', _day, 20, 0, 5000, (v) => _day = v),
        _stepper('Pause after this many swipes', _burst, 5, 0, 500, (v) => _burst = v),
        if (_burst > 0) ...[
          _stepper('…within', _window, 5, 5, 120, (v) => _window = v, unit: ' min'),
          _stepper('Pause for', _pause, 1, 1, 120, (v) => _pause = v, unit: ' min'),
        ],
        const SizedBox(height: 8),
        Text('Turning a part up or off later takes a typed paragraph, like the other limits. Making it stricter is free.', style: t.textTheme.bodySmall),
        if (_dirty) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: Text(_draft.on ? 'Save' : 'Turn off')),
        ],
      ]),
      if (notes.isNotEmpty)
        _card([
          Text('Your pattern', style: t.textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(n)),
          if (h != null && h.suggestedMaxSwipes > 0 && _day == 0) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() { _day = h.suggestedMaxSwipes; _dirty = true; }),
              child: Text('Suggest ${h.suggestedMaxSwipes} swipes a day'),
            ),
          ],
          const SizedBox(height: 6),
          Text('Worked out on this phone from your own counts. Nothing is set unless you save it.', style: t.textTheme.bodySmall),
        ]),
    ]);
  }
}
