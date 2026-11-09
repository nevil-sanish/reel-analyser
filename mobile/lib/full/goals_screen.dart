import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import 'blocker.dart';
import 'full_bridge.dart';
import 'goal_store.dart';
import 'goals.dart';
import 'full_features.dart';
import 'detect_consent.dart';
import 'handle_change_screen.dart';
import '../ui/liquid.dart';
import '../ui/motion.dart';

/// Settings → Daily goals (full build). A target of GitHub commits, Codeforces problems and LeetCode problems a day. Miss a
/// day and Instagram (and YouTube, if chosen) is blocked the next day: 1 day after the first miss, 2 after two in a row, 4
/// after three or more.
class GoalsScreen extends StatefulWidget {
  final AppServices services;

  /// Inside the Blocker tab: no app bar of its own, and room under the floating tab bar.
  final bool embedded;
  const GoalsScreen(this.services, {this.embedded = false, super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  AppServices get s => widget.services;
  final _bridge = BlockerBridge();
  final _enabled = {for (final k in goalSources) k: false};
  final _handles = {for (final k in goalSources) k: TextEditingController()};
  final _targets = {'github': 1, 'codeforces': 2, 'leetcode': 1};
  final _apps = <String>{'instagram'};
  var _locked = <String, String>{};
  var _loaded = false;
  var _hasGoals = false;
  var _consent = false;
  var _serviceOn = true;
  var _streak = 0;
  String? _until;
  List<(String, Map<String, int?>, bool?, int)> _days = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _handles.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _editable => goalsEditable(DateTime.now(), hasGoals: _hasGoals);

  Future<void> _load() async {
    final cfg = GoalConfig.parse(await (await GoalStore.of(s.library)).latestGoalConfigJson());
    final (streak, until) = await (await GoalStore.of(s.library)).goalPenaltyRow();
    final days = await (await GoalStore.of(s.library)).goalDays(limit: 14);
    final locked = await (await GoalStore.of(s.library)).lockedHandles();
    final consent = await _bridge.consent();
    final status = await FullBridge().status();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _hasGoals = cfg != null && cfg.goals.isNotEmpty;
      if (cfg != null) {
        for (final k in goalSources) {
          _enabled[k] = false;
        }
        for (final g in cfg.goals) {
          _enabled[g.source] = true;
          _handles[g.source]!.text = g.handle;
          _targets[g.source] = g.target;
        }
        _apps
          ..clear()
          ..addAll(cfg.blockApps);
      }
      _streak = streak;
      _until = until;
      _days = days;
      _locked = locked;
      _consent = consent;
      _serviceOn = status.serviceEnabled;
    });
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Goal? _goal(String k) {
    final h = _handles[k]!.text.trim();
    return _enabled[k]! && validHandle(k, h) ? Goal(k, h, _targets[k]!) : null;
  }

  Future<void> _save() async {
    final goals = <Goal>[];
    for (final k in goalSources) {
      if (!_enabled[k]!) continue;
      var g = _goal(k);
      if (g != null && _locked.containsKey(k) && _locked[k] != g.handle) g = null;
      if (g == null) {
        Haptics.warning();
        return _say('Check the ${goalNames[k]!.split(' ').first} username: letters, digits and - _ . only.');
      }
      goals.add(g);
    }
    if (goals.isEmpty) return _say('Turn on at least one goal.');
    if (_apps.isEmpty) return _say('Pick at least one app to block.');
    if (!_consent) {
      if (!await askDetectionConsent(context)) return _say('Blocking needs your OK to read which app is open.');
      await _bridge.setConsent(true);
    }
    Haptics.success();
    await (await GoalStore.of(s.library)).saveGoalConfig(dateOf(DateTime.now()), GoalConfig(goals, {..._apps}).toJson());
    _say(_hasGoals ? 'Saved. It counts from today.' : 'Daily goals are on. They count from today.');
    try {
      await goalEngine(s).run(); // also tells the blocker which apps to block
    } on Object catch (_) {}
    _load();
  }

  Future<void> _change(String k) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => HandleChangeScreen(s, k, _locked[k]!)));
    if (changed == true) {
      try {
        await goalEngine(s).run();
      } on Object catch (_) {}
      _say('Username changed. It counts from today.');
    }
    _load();
  }

  Widget _stepper(String k, bool locked) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Text('Each day', style: t.bodyMedium),
      const Spacer(),
      IconButton.outlined(
        onPressed: locked || _targets[k]! <= 1 ? null : () => setState(() { Haptics.select(); _targets[k] = _targets[k]! - 1; }),
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(width: 56, child: Center(child: Text('${_targets[k]}', style: t.titleLarge))),
      IconButton.outlined(
        onPressed: locked || _targets[k]! >= 100 ? null : () => setState(() { Haptics.select(); _targets[k] = _targets[k]! + 1; }),
        icon: const Icon(Icons.add_rounded),
      ),
      const SizedBox(width: 8),
      Text(goalUnits[k]!, style: t.bodyMedium),
    ]);
  }

  Widget _source(String k, bool locked, int index) {
    final t = Theme.of(context);
    final on = _enabled[k]!;
    final fixed = _locked.containsKey(k);
    return Reveal(
      index: index,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(goalNames[k]!, style: t.textTheme.titleMedium),
              value: on,
              onChanged: locked ? null : (v) => setState(() { Haptics.select(); _enabled[k] = v; }),
            ),
            if (on) ...[
              TextField(
                controller: _handles[k],
                enabled: !locked && !fixed,
                maxLength: 40,
                autocorrect: false,
                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: k == 'github' ? 'GitHub username' : k == 'codeforces' ? 'Codeforces handle' : 'LeetCode username',
                  counterText: '',
                  errorText: _handles[k]!.text.isNotEmpty && !validHandle(k, _handles[k]!.text.trim()) ? 'Not a valid name' : null,
                ),
              ),
              const SizedBox(height: 12),
              _stepper(k, locked),
              const SizedBox(height: 8),
              if (fixed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _change(k),
                    icon: const Icon(Icons.lock_outline_rounded, size: 18),
                    label: const Text('Change username'),
                  ),
                ),
              if (k == 'github') Text('Counts commits made in public repositories.', style: t.textTheme.bodySmall),
              if (k == 'leetcode')
                Text('LeetCode has no official API. This reads your public profile, so it may stop working. Check LeetCode\'s terms.', style: t.textTheme.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }

  String _longDate(String d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final x = parseDate(d);
    return '${x.day} ${m[x.month - 1]}';
  }

  Widget _shell({PreferredSizeWidget? appBar, required Widget body}) => widget.embedded ? body : LiquidScaffold(appBar: appBar, body: body);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (!_loaded) return _shell(appBar: AppBar(title: const Text('Daily goals')), body: const SizedBox());
    final locked = !_editable;
    final today = dateOf(DateTime.now());
    final blocked = _until != null && _until!.compareTo(today) >= 0;
    return _shell(
      appBar: AppBar(title: const Text('Daily goals')),
      body: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, widget.embedded ? 120 : 32), children: [
        Reveal(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(blocked ? 'Blocked until ${_longDate(_until!)}' : _hasGoals ? 'On track' : 'Not set up', style: t.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  _hasGoals ? 'Missed days in a row: $_streak' : 'Set a daily target. If you miss a day, Instagram is blocked the next day.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Miss one day: blocked for 1 day. Miss two in a row: 2 days. Three or more in a row: 4 days. A day you meet your goals ends the run. '
                  'Each day is checked automatically just after midnight, by your phone, against your local day. There is nothing to press. '
                  'Usernames are locked once used; changing one takes a day and a written reason.',
                  style: t.textTheme.bodySmall,
                ),
                if (_hasGoals && !_consent) ...[
                  const SizedBox(height: 10),
                  Text('Reading which app is open is off, so nothing can be blocked. Turn it on in Settings → Set up Insights.',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
                ],
                if (!_serviceOn) ...[
                  const SizedBox(height: 10),
                  Text('Accessibility is off, so nothing can be blocked yet. Turn it on in Settings → Set up Insights.',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
                ],
              ]),
            ),
          ),
        ),
        if (locked)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: t.colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Goals are locked for today. You can change them between 00:00 and 00:10, and a change counts from that day.'),
            ),
          ),
        for (final (i, k) in goalSources.indexed) _source(k, locked, i + 1),
        Reveal(
          index: 4,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('What a miss blocks', style: t.textTheme.titleMedium),
                for (final (k, label) in [('instagram', 'Instagram (the whole app)'), ('youtube', 'YouTube (the whole app)')])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    value: _apps.contains(k),
                    onChanged: locked ? null : (v) => setState(() { Haptics.select(); v == true ? _apps.add(k) : _apps.remove(k); }),
                  ),
                Text('A penalty cannot be cancelled for the day. It ends after its last day.', style: t.textTheme.bodySmall),
                const SizedBox(height: 14),
                FilledButton(onPressed: locked ? null : _save, child: Text(_hasGoals ? 'Save changes' : 'Turn the goals on')),
              ]),
            ),
          ),
        ),
        if (_days.isNotEmpty)
          Reveal(
            index: 5,
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Recent days', style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (final (d, counts, met, streak) in _days)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(met == null ? Icons.help_outline_rounded : met ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: met == null ? t.colorScheme.onSurfaceVariant : met ? t.colorScheme.primary : t.colorScheme.error),
                      title: Text(_longDate(d)),
                      subtitle: Text([for (final e in counts.entries) '${goalNames[e.key]!.split(' ').first} ${e.value ?? '?'}'].join(' · ')),
                      trailing: met == false ? Text('miss $streak') : null,
                    ),
                ]),
              ),
            ),
          ),
        Text(
          'Only your public username is sent, to GitHub, Codeforces and LeetCode, to read your own activity. Nothing is stored outside this phone, '
          'and there is no account or server. Erase all my data removes it.',
          style: t.textTheme.bodySmall,
        ),
      ]),
    );
  }
}
