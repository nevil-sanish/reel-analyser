import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import 'blocker.dart';
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
  final _edits = <String, _RuleEdit>{};

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
      if (keepEdits && _edits.isNotEmpty) return;
      // Show what is waiting for midnight if there is a change, else what is in force.
      final c = st.pending ?? st.active;
      _mode = c?.mode ?? 'shared';
      _items
        ..clear()
        ..addAll(c?.items ?? const <String>{});
      _edits
        ..clear()
        ..addAll({
          for (final k in ['all', ...blockSurfaces]) k: _RuleEdit(c?.rules[k]),
        });
    });
  }

  void _say(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (_items.isEmpty) return _say('Pick at least one thing to block.');
    if (!_consent) {
      if (!await askDetectionConsent(context)) return _say('The blocker needs your OK to read the reel screens.');
      await _bridge.setConsent(true);
      _consent = true;
    }
    final keys = _mode == 'shared' ? ['all'] : _items.toList();
    final c = BlockConfig(
      _mode,
      {..._items},
      {for (final k in keys) k: _edits[k]!.rule},
    );
    if (c.rules.values.every(
      (r) => r.limitMin == null && r.intervals.isEmpty,
    )) {
      return _say('Set a daily limit or at least one time slot.');
    }
    final before = _st?.active;
    if (before != null) {
      final ask = (await widget.services.chatProviders()).isEmpty ? null : widget.services.askOnce;
      if (!mounted) return;
      final ok = await askParagraph(
        context,
        title: 'Change the reel limits',
        intro: 'To change rules that are already on, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
            'Pasting is not accepted. Your paragraph is checked with your own AI key and is not stored. '
            'If it is accepted, the new rules start at 00:00 tonight; until then today\'s rules stay.',
        action: 'Check and save',
        verify: (text) => judgeRuleChange(ask, before: before, after: c, reason: text),
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
    _edits.clear();
    _load();
  }

  Future<void> _cancelToday() async {
    final ok = await askParagraph(
      context,
      title: 'Turn off for today',
      intro: 'To turn the block off until midnight, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
          'Pasting is not accepted, and typing very fast locks the field until you stop for 2 seconds. The text is not sent or stored.',
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

  String _used(BlockerState st, BlockConfig c) {
    String m(int ms) => '${ms ~/ 60000} min';
    return [
      for (final k in blockSurfaces)
        if (c.items.contains(k))
          '${surfaceNames[k]!.split(' (').first}: ${m(st.used[k] ?? 0)}',
    ].join('  ·  ');
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
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BlockHistoryScreen(_bridge)),
            ),
          ),
        ],
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
                    const SizedBox(height: 10),
                    Text('Today: ${_used(st, st.active!)}'),
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
                    'A reel can be watched only when both the limit and the time slots allow it.',
                    style: t.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _save,
                    child: Text(
                      st.active == null
                          ? 'Turn the blocker on'
                          : 'Save changes',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (st.active != null) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: const Icon(Icons.timer_off_outlined),
              label: Text(
                st.suspendedToday
                    ? 'Already off for today'
                    : 'Turn off for today (50-word paragraph)',
              ),
              onPressed: st.suspendedToday ? null : _cancelToday,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Remove the blocker for good'),
              onPressed: () async {
                final done = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RemoveBlockerScreen(_bridge),
                  ),
                );
                if (done == true) _load();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Removing the blocker for good takes a paragraph written by hand about why.
class RemoveBlockerScreen extends StatefulWidget {
  final BlockerBridge bridge;
  const RemoveBlockerScreen(this.bridge, {super.key});

  @override
  State<RemoveBlockerScreen> createState() => _RemoveBlockerScreenState();
}

class _RemoveBlockerScreenState extends State<RemoveBlockerScreen> {
  final _guard = ParagraphGuard();
  final _c = TextEditingController();
  String? _msg;

  void _changed(String v) {
    final refused = _guard.accept(v, DateTime.now());
    if (refused != null) {
      // Put the old text back: a paste or a burst of fast typing isn't taken.
      _c.value = TextEditingValue(
        text: _guard.text,
        selection: TextSelection.collapsed(offset: _guard.text.length),
      );
      setState(() => _msg = refused);
      return;
    }
    if (_msg != null) setState(() => _msg = null);
  }

  Future<void> _remove() async {
    final bad = _guard.check();
    if (bad != null) return setState(() => _msg = bad);
    await widget.bridge.removeForGood();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LiquidScaffold(
      appBar: AppBar(title: const Text('Remove for good')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Why do you need to remove the blocker for good?',
            style: t.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Write at least ${ParagraphGuard.minWords} words in your own words, by hand. Pasting is not accepted, and the text is '
            'checked for wording typical of AI. If you only need a break, turn it off for today instead.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            minLines: 6,
            maxLines: 12,
            onChanged: _changed,
            // No Paste in the menu.
            contextMenuBuilder: (context, state) =>
                AdaptiveTextSelectionToolbar.editable(
                  clipboardStatus: ClipboardStatus.notPasteable,
                  onCopy: null,
                  onCut: null,
                  onPaste: null,
                  onSelectAll: null,
                  onLookUp: null,
                  onSearchWeb: null,
                  onShare: null,
                  onLiveTextInput: null,
                  anchors: state.contextMenuAnchors,
                ),
            decoration: const InputDecoration(hintText: 'Type here…'),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_msg!, style: TextStyle(color: t.colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _remove,
            child: const Text('Remove the blocker'),
          ),
        ],
      ),
    );
  }
}

class BlockHistoryScreen extends StatelessWidget {
  final BlockerBridge bridge;
  const BlockHistoryScreen(this.bridge, {super.key});

  @override
  Widget build(BuildContext context) => LiquidScaffold(
    appBar: AppBar(title: const Text('Blocker history')),
    body: FutureBuilder<List<BlockEvent>>(
      future: bridge.history(),
      builder: (c, snap) {
        final list = snap.data;
        if (list == null) return const SizedBox();
        if (list.isEmpty) {
          return const Center(
            child: Text(
              'Nothing yet. Days you pass the limit or try to cancel show here.',
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final e in list)
              ListTile(
                leading: Icon(switch (e.kind) {
                  'cancelled' || 'removed' => Icons.lock_open_rounded,
                  'kept' => Icons.favorite_rounded,
                  'limit' || 'schedule' => Icons.block_rounded,
                  _ => Icons.history_rounded,
                }),
                title: Text(e.label),
                subtitle: Text(
                  '${e.at.day}/${e.at.month}/${e.at.year}  ${TimeSlot.hhmm(e.at.hour * 60 + e.at.minute)}',
                ),
              ),
          ],
        );
      },
    ),
  );
}
