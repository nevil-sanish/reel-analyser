import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import 'blocker.dart';
import 'limit_bar.dart';
import 'detect_consent.dart';
import 'paragraph_gate.dart';
import '../ui/liquid.dart';
import '../ui/motion.dart';

/// One rule being edited: a limit (minutes or hours) and the times of day the reels are allowed.
class _RuleEdit {
  final limit = TextEditingController();
  bool hours = false;
  List<TimeSlot> intervals = [];

  _RuleEdit([BlockRule? r]) {
    final m = r?.limitMin;
    if (m != null) {
      hours = m % 60 == 0;
      limit.text = '${hours ? m ~/ 60 : m}';
    }
    intervals = [...?r?.intervals];
  }

  int? get minutes {
    final v = int.tryParse(limit.text.trim());
    return v == null || v <= 0 ? null : (hours ? v * 60 : v);
  }

  BlockRule get rule => BlockRule(minutes, intervals);
}

/// Settings → Reel blocker (full build). Limits and schedules for Instagram Reels, YouTube Shorts and reels in a browser.
class BlockerScreen extends StatefulWidget {
  final AppServices services;

  /// Inside the Blocker tab: no app bar of its own (the tab has one), and room under the floating tab bar.
  final bool embedded;
  const BlockerScreen(this.services, {this.embedded = false, super.key});

  @override
  State<BlockerScreen> createState() => _BlockerScreenState();
}

class _BlockerScreenState extends State<BlockerScreen>
    with WidgetsBindingObserver {
  final _bridge = BlockerBridge();
  BlockerState? _st;
  var _consent = false;
  var _mode = 'shared';
  final _items = <String>{};
  final _whole = <String>{};
  final _edits = <String, _RuleEdit>{};
  var _editing = false;
  var _baseline = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // The bars follow the time as it is used.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _load(keepEdits: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _load(keepEdits: true);
    }
  }

  Future<void> _load({bool keepEdits = false}) async {
    final st = await _bridge.state();
    final consent = await _bridge.consent();
    if (!mounted) return;
    setState(() {
      _st = st;
      _consent = consent;
      if (keepEdits && (_editing || _dirty)) return; // the timer must not wipe what is being typed
      // Show what is waiting for midnight if there is a change, else what is in force.
      final c = st.pending ?? st.active;
      _mode = c?.mode ?? 'shared';
      _items
        ..clear()
        ..addAll(c?.items ?? const <String>{});
      _whole
        ..clear()
        ..addAll(c?.wholeApp ?? const <String>{});
      _edits
        ..clear()
        ..addAll({
          for (final k in ['all', ...blockSurfaces]) k: _RuleEdit(c?.rules[k]),
        });
      _baseline = _build().toJson();
    });
  }

  void _say(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int _nowMinute() {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  /// What the screen holds now, as [_save] would store it.
  BlockConfig _build() {
    final keys = _mode == 'shared' ? ['all'] : [for (final k in blockSurfaces) if (_items.contains(k)) k];
    return BlockConfig(_mode, {..._items}, {for (final k in keys) k: _edits[k]!.rule}, wholeApp: _whole.intersection(_items));
  }

  bool get _dirty => _edits.isNotEmpty && _build().toJson() != _baseline;

  Future<void> _save() async {
    if (_items.isEmpty) return _say('Pick at least one thing to block.');
    if (!_consent) {
      if (!await askDetectionConsent(context)) return _say('The blocker needs your OK to read the reel screens.');
      await _bridge.setConsent(true);
      _consent = true;
    }
    final c = _build();
    if (c.rules.values.every(
      (r) => r.limitMin == null && r.intervals.isEmpty,
    )) {
      return _say('Set a daily limit or at least one time slot.');
    }
    final before = _st?.active;
    if (before != null) {
      if (!mounted) return;
      final ok = await askParagraph(
        context,
        title: 'Change the reel limits',
        intro: 'To change rules that are already on, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
            'Pasting is not accepted. It is checked on your phone only and is not stored. '
            'If it is accepted, the new rules start at 00:00 tonight; until then today\'s rules stay.',
        action: 'Check and save',
      );
      if (!ok || !mounted) return;
    }
    Haptics.medium();
    final r = await _bridge.save(c);
    if (!mounted) return;
    _say(switch (r) {
      'ok' => before == null ? 'The blocker is on.' : 'Saved. The new rules start at 00:00 tonight.',
      _ => 'Those rules are not valid.',
    });
    _editing = false;
    _edits.clear();
    _load();
  }

  Future<void> _removeForGood() async {
    final ok = await askParagraph(
      context,
      title: 'Turn off for good',
      intro: 'To turn off the blocker and remove all its rules, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
          'Pasting is not accepted, and typing very fast locks the field until you stop for 2 seconds. It is checked on your phone only and is not stored.',
      action: 'Turn off the blocker',
    );
    if (!ok || !mounted) return;
    await _bridge.removeForGood();
    _say('The blocker is removed.');
    _editing = false;
    _edits.clear();
    _load();
  }

  Future<void> _cancelToday() async {
    final ok = await askParagraph(
      context,
      title: 'Turn off for today',
      intro: 'To turn the block off until midnight, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
          'Pasting is not accepted, and typing very fast locks the field until you stop for 2 seconds. It is checked on your phone only and is not stored.',
      action: 'Turn off for today',
    );
    if (!ok || !mounted) return;
    await _bridge.cancelToday();
    _say('The block is off for today. It comes back at midnight.');
    _load();
  }

  Future<void> _addInterval(_RuleEdit e) async {
    final a = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
      helpText: 'Allowed from',
    );
    if (a == null || !mounted) return;
    final b = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (a.hour + 1) % 24, minute: a.minute),
      helpText: 'Allowed until',
    );
    if (b == null) return;
    final i = TimeSlot(a.hour * 60 + a.minute, b.hour * 60 + b.minute);
    if (i.start == i.end) return _say('The start and the end are the same.');
    setState(() => e.intervals = [...e.intervals, i]);
  }

  Widget _ruleEditor(String key, String title) {
    final e = _edits[key]!;
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: e.limit,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Daily limit',
              helperText: 'Empty = no limit',
              isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('min')),
                ButtonSegment(value: true, label: Text('hours')),
              ],
              selected: {e.hours},
              onSelectionChanged: (v) => setState(() => e.hours = v.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Allowed only at (none = any time)', style: t.textTheme.bodySmall),
        Wrap(
          spacing: 8,
          children: [
            for (final i in e.intervals)
              InputChip(
                label: Text('$i'),
                onDeleted: () => setState(
                  () => e.intervals = [...e.intervals]..remove(i),
                ),
              ),
            ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add time'),
                onPressed: () => _addInterval(e),
              ),
          ],
        ),
      ],
    );
  }

  /// A bar for each timer in force: the one shared limit, or one per item. Rules with only time slots have no timer.
  List<Widget> _bars(BlockerState st, BlockConfig c) {
    final out = <Widget>[];
    void slots(String name, BlockRule? r) {
      if (r != null && r.intervals.isNotEmpty) out.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text('$name: allowed only at ${r.intervals.join(', ')}')));
    }

    if (c.mode == 'shared') {
      final r = c.rules['all'];
      final used = c.items.fold<int>(0, (n, k) => n + (st.used[k] ?? 0));
      if (r?.limitMin != null) out.add(LimitBar(label: 'All chosen together', usedMs: used, limitMin: r!.limitMin!));
      slots('All chosen together', r);
    } else {
      for (final k in blockSurfaces) {
        if (!c.items.contains(k)) continue;
        final r = c.rules[k];
        final name = surfaceNames[k]!.split(' (').first;
        if (r?.limitMin != null) out.add(LimitBar(label: name, usedMs: st.used[k] ?? 0, limitMin: r!.limitMin!));
        slots(name, r);
      }
    }
    return out;
  }

  Widget _shell({PreferredSizeWidget? appBar, required Widget body}) => widget.embedded ? body : LiquidScaffold(appBar: appBar, body: body);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final st = _st;
    if (st == null) {
      return _shell(
        appBar: AppBar(title: const Text('Reel blocker')),
        body: const SizedBox(),
      );
    }
    final p = st.pending;
    final startsAt = p == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(st.pendingFrom);
    return _shell(
      appBar: AppBar(
        title: const Text('Reel blocker'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, widget.embedded ? 120 : 32),
        children: [
          Card(
          margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    st.active == null
                        ? 'Not set up'
                        : st.suspendedToday
                        ? 'Off for today'
                        : 'On',
                    style: t.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Blocks only the Reels, Shorts and reel pages you pick, never the rest of the app. It needs the Accessibility service '
                    '(Settings → Set up Insights). It looks only at whether a reel or short is on screen, and in a browser at the address bar. '
                    'Nothing is recorded or sent.',
                    style: t.textTheme.bodySmall,
                  ),
                  if (st.active != null) ...[
                    ..._bars(st, st.active!),
                  ],
                  if (st.suspendedToday) ...[
                    const SizedBox(height: 12),
                    const Text('You turned the block off for today. It comes back at midnight.'),
                  ],
                ],
              ),
            ),
          ),
          if (!_consent)
          Card(
          margin: const EdgeInsets.only(bottom: 12),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Reading the reel screens is off'),
              subtitle: const Text('Nothing is read and nothing is blocked until you allow it. No screenshots or recordings, ever.'),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  if (!await askDetectionConsent(context)) return;
                  await _bridge.setConsent(true);
                  _load(keepEdits: true);
                },
                child: const Text('Allow'),
              ),
            ),
          ),
          if (p != null)
            Card(
          margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'A change is waiting. It starts at ${TimeSlot.hhmm(startsAt!.hour * 60 + startsAt.minute)} '
                  '(${startsAt.day}/${startsAt.month}). Until then the old rules are in force.',
                ),
              ),
            ),
          if (st.active == null || _editing)
          Card(
          margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What to block', style: t.textTheme.titleMedium),
                  for (final k in blockSurfaces)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(surfaceNames[k]!),
                      value: _items.contains(k),
                      onChanged: (v) => setState(
                        () => v == true ? _items.add(k) : _items.remove(k),
                      ),
                    ),
                  for (final k in blockSurfaces)
                    if (wholeAppSurfaces.contains(k) && _items.contains(k))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${surfaceNames[k]!.split(' ').first}: what to count and block', style: t.textTheme.bodySmall),
                            const SizedBox(height: 4),
                            SegmentedButton<bool>(
                              segments: [
                                ButtonSegment(value: false, label: Text(k == 'youtube' ? 'Shorts only' : k == 'snapchat' ? 'Spotlight only' : 'Reels only')),
                                ButtonSegment(value: true, label: Text('Whole app')),
                              ],
                              selected: {_whole.contains(k)},
                              onSelectionChanged: (v) => setState(() => v.first ? _whole.add(k) : _whole.remove(k)),
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'shared',
                        label: Text('One limit for all'),
                      ),
                      ButtonSegment(
                        value: 'separate',
                        label: Text('Each its own'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) => setState(() => _mode = v.first),
                  ),
                  const SizedBox(height: 16),
                  if (_mode == 'shared')
                    _ruleEditor('all', 'All chosen together')
                  else
                    for (final k in blockSurfaces)
                      if (_items.contains(k)) ...[
                        _ruleEditor(
                          k,
                          surfaceNames[k]!.split(' (').first,
                        ),
                        const SizedBox(height: 16),
                      ],
                  const SizedBox(height: 8),
                  Text(
                    'A reel or short can be watched only when both the limit and the time slots allow it. With Whole app, all your time in Instagram or YouTube counts, and past the limit or outside the time slots the app itself does not open.',
                    style: t.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_dirty)
                    FilledButton(
                      onPressed: _save,
                      child: Text(st.active == null ? 'Turn the blocker on' : 'Save changes'),
                    ),
                  // Pausing makes sense only while the block is really stopping you.
                  if (st.active != null && _editing && !st.suspendedToday && blockInEffect(st.active, st.used, _nowMinute())) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _cancelToday, child: const Text('Turn off for today (50-word paragraph)')),
                  ],
                  if (st.active != null && _editing && st.suspendedToday) ...[
                    const SizedBox(height: 8),
                    const OutlinedButton(onPressed: null, child: Text('Already off for today')),
                  ],
                  if (st.active != null && _editing) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        _editing = false;
                        _load();
                      },
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (st.active != null && !_editing) ...[
            FilledButton.tonal(onPressed: () => setState(() => _editing = true), child: const Text('Edit')),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Turn off permanently'),
              onPressed: _removeForGood,
            ),
          ],
        ],
      ),
    );
  }
}

