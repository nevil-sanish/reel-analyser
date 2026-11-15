import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../ui/motion.dart';
import 'blocker.dart';
import 'detect_consent.dart';
import 'full_bridge.dart';
import 'limit_bar.dart';
import 'limits.dart';
import 'paragraph_gate.dart';

/// Blocker → Apps & sites: a daily time for any app or website. When the time is used up, the app or site is blocked until midnight.
class LimitsScreen extends StatefulWidget {
  final AppServices services;
  const LimitsScreen(this.services, {super.key});

  @override
  State<LimitsScreen> createState() => _LimitsScreenState();
}

class _LimitsScreenState extends State<LimitsScreen> with WidgetsBindingObserver {
  final _bridge = LimitsBridge();
  final _blocker = BlockerBridge();
  LimitsState? _st;
  var _draft = <LimitItem>[];
  var _baseline = '';
  var _editing = false;
  var _consent = false;
  Timer? _timer;

  bool get _dirty => limitsSignature(_draft) != _baseline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // The bars follow the time as it is used.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _load(keepDraft: true);
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
    if (s == AppLifecycleState.resumed) _load(keepDraft: true);
  }

  Future<void> _load({bool keepDraft = false}) async {
    final st = await _bridge.state();
    final consent = await _blocker.consent();
    if (!mounted) return;
    setState(() {
      _st = st;
      _consent = consent;
      if (keepDraft && (_editing || _dirty)) return; // the timer must not wipe what is being typed
      _draft = [...(st.pending ?? st.active)];
      _baseline = limitsSignature(_draft);
    });
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<int?> _askMinutes(String title, {int? initial}) async {
    final c = TextEditingController(text: initial == null ? '' : '$initial');
    final v = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Minutes a day', helperText: '0 = blocked all day. 60 = 1 hour. Most is 1440.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(c.text.trim());
              Navigator.pop(d, n == null || n > 1440 ? null : n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return v;
  }

  Future<void> _addApp() async {
    final apps = await _bridge.installedApps();
    if (!mounted) return;
    final taken = {for (final i in _draft) i.id};
    final pick = await showModalBottomSheet<InstalledApp>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AppPicker([for (final a in apps) if (!taken.contains(a.pkg)) a]),
    );
    if (pick == null || !mounted) return;
    final m = await _askMinutes('Daily time for ${pick.label}');
    if (m == null) return;
    setState(() => _draft = [..._draft, LimitItem('app', pick.pkg, pick.label, m)]);
  }

  Future<void> _addSite() async {
    final c = TextEditingController();
    final host = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add a website'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Address', hintText: 'youtube.com', helperText: 'The site and every page on it'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, hostOf(c.text)), child: const Text('Next')),
        ],
      ),
    );
    if (host == null || !mounted) return;
    if (_draft.any((i) => i.key == 'site:$host')) return _say('$host is already in the list.');
    final m = await _askMinutes('Daily time for $host');
    if (m == null) return;
    setState(() => _draft = [..._draft, LimitItem('site', host, host, m)]);
  }

  Future<void> _change(LimitItem i) async {
    final m = await _askMinutes('Daily time for ${i.label}', initial: i.limitMin);
    if (m == null) return;
    setState(() => _draft = [for (final x in _draft) x.key == i.key ? x.withLimit(m) : x]);
  }

  Future<void> _save() async {
    if (_draft.isEmpty) return _say('Add at least one app or website.');
    final before = _st?.active ?? const <LimitItem>[];
    final immediate = before.isEmpty || isStricter(before, _draft);
    // Asked at the first set-up even if reel reading is already allowed: these limits read more (the app in front, the address bar).
    if (!_consent || before.isEmpty) {
      if (!await askDetectionConsent(context, limits: true)) return _say('Nothing was saved: the time limits need your OK to see which app or site is open.');
      await _blocker.setConsent(true);
      _consent = true;
    }
    if (!immediate) {
      if (!mounted) return;
      final ok = await askParagraph(
        context,
        title: 'Change the time limits',
        intro: 'To loosen limits that are already on, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
            'Pasting is not accepted. It is checked on your phone only and is not stored. '
            'If it is accepted, the new limits start at 00:00 tonight; until then today\'s limits stay.',
        action: 'Check and save',
      );
      if (!ok || !mounted) return;
    }
    Haptics.medium();
    final r = await _bridge.save(_draft, immediate: immediate);
    if (!mounted) return;
    _say(r != 'ok' ? 'Those limits are not valid.' : before.isEmpty ? 'The time limits are on.' : immediate ? 'Saved.' : 'Saved. The new limits start at 00:00 tonight.');
    setState(() => _editing = false);
    _load();
  }

  Future<void> _removeForGood() async {
    final ok = await askParagraph(
      context,
      title: 'Turn off for good',
      intro: 'To remove all the app and website time limits, write at least ${ParagraphGuard.minWords} words, by hand, about why. '
          'Pasting is not accepted. It is checked on your phone only and is not stored.',
      action: 'Remove the limits',
    );
    if (!ok || !mounted) return;
    await _bridge.remove();
    _say('The time limits are removed.');
    setState(() => _editing = false);
    _load();
  }

  /// Apps are timed from Android's usage data; without Usage access they are neither counted nor blocked.
  Widget _usageWarning(LimitsState st) {
    final hasApp = {...st.active, ..._draft}.any((i) => !i.isSite);
    if (!hasApp || st.usageAccess) return const SizedBox();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: const Text('Usage access is off'),
        subtitle: const Text('Apps are timed with it. Until you allow it, app limits count nothing and block nothing.'),
        trailing: FilledButton.tonal(onPressed: () => FullBridge().open('openUsageAccess'), child: const Text('Allow')),
      ),
    );
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
    final on = st.active.isNotEmpty;
    final startsAt = st.pending == null ? null : DateTime.fromMillisecondsSinceEpoch(st.pendingFrom);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        _usageWarning(st),
        if (on && !_editing) ...[
          _card([
            Text('On', style: t.textTheme.titleLarge),
            for (final i in st.active) LimitBar(label: '${i.label}${i.isSite ? ' (website)' : ''}', usedMs: st.used[i.key] ?? 0, limitMin: i.limitMin),
            const SizedBox(height: 10),
            Text('When the time is used up, the app or website is blocked until midnight.', style: t.textTheme.bodySmall),
          ]),
          if (startsAt != null)
            _card([Text('A change is waiting. It starts at 00:00 (${startsAt.day}/${startsAt.month}). Until then the old limits are in force.')]),
          FilledButton.tonal(onPressed: () => setState(() => _editing = true), child: const Text('Edit')),
          const SizedBox(height: 8),
          TextButton.icon(icon: const Icon(Icons.delete_forever_outlined), label: const Text('Turn off permanently'), onPressed: _removeForGood),
        ] else ...[
          _card([
            Text(on ? 'Edit the limits' : 'Time limits for apps and websites', style: t.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Pick an app or a website and the time you allow it each day. Past that time it is blocked until midnight. '
              'Apps are timed with Android\'s Usage access. Websites are timed with the Accessibility service, which reads the browser\'s address bar only for the sites you add. '
              'Both also need the Accessibility service on, so the block screen can open over the app. Nothing is recorded or sent.',
              style: t.textTheme.bodySmall,
            ),
            if (!_consent) ...[
              const SizedBox(height: 8),
              Text('Reading the screens is off. You are asked to allow it when you save.', style: t.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            for (final i in _draft)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(i.isSite ? Icons.language_rounded : Icons.apps_rounded),
                title: Text(i.label),
                subtitle: Text('${i.isSite ? 'Website' : 'App'} · ${minutesText(i.limitMin)} a day${st.active.any((a) => a.key == i.key) ? ' · ${minutesText((st.used[i.key] ?? 0) ~/ 60000)} used today' : ''}'),
                onTap: () => _change(i),
                trailing: IconButton(
                  tooltip: 'Remove from the list',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _draft = [for (final x in _draft) if (x.key != i.key) x]),
                ),
              ),
            Wrap(spacing: 8, children: [
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add app'), onPressed: _addApp),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add website'), onPressed: _addSite),
            ]),
            if (_dirty && _draft.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: _save, child: Text(on ? 'Save changes' : 'Turn the limits on')),
            ],
          ]),
          if (on)
            OutlinedButton(
              onPressed: () => setState(() {
                _editing = false;
                _draft = [...(st.pending ?? st.active)];
              }),
              child: const Text('Cancel'),
            ),
        ],
      ],
    );
  }
}

class _AppPicker extends StatefulWidget {
  final List<InstalledApp> apps;
  const _AppPicker(this.apps);

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  var _q = '';

  @override
  Widget build(BuildContext context) {
    final list = [for (final a in widget.apps) if (a.label.toLowerCase().contains(_q.toLowerCase())) a];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search your apps', isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No app found.'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => ListTile(title: Text(list[i].label), subtitle: Text(list[i].pkg), onTap: () => Navigator.pop(context, list[i])),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
