import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../ui/liquid.dart';
import '../ui/motion.dart';
import 'blocker.dart';
import 'full_features.dart';
import 'goal_store.dart';
import 'goals.dart';

/// Changing a username for a goal. A username is locked once it is used. To change it: ask today, come back on a later day,
/// write at least 50 words by hand about why, and the reason is checked by your own AI provider. Pops `true` when changed.
class HandleChangeScreen extends StatefulWidget {
  final AppServices services;
  final String source;
  final String oldHandle;
  const HandleChangeScreen(this.services, this.source, this.oldHandle, {super.key});

  @override
  State<HandleChangeScreen> createState() => _HandleChangeScreenState();
}

class _HandleChangeScreenState extends State<HandleChangeScreen> {
  AppServices get s => widget.services;
  final _guard = ParagraphGuard();
  final _reason = TextEditingController();
  final _name = TextEditingController();
  ChangeStep? _step;
  var _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await GoalStore.of(s.library);
    final step = changeStep(await store.changeRequestedOn(), dateOf(DateTime.now()));
    if (mounted) setState(() => _step = step);
  }

  Future<void> _ask() async {
    Haptics.select();
    await (await GoalStore.of(s.library)).requestChange(dateOf(DateTime.now()));
    await _load();
  }

  void _changed(String v) {
    final refused = _guard.accept(v, DateTime.now());
    if (refused != null) {
      _reason.value = TextEditingValue(text: _guard.text, selection: TextSelection.collapsed(offset: _guard.text.length));
      setState(() => _msg = refused);
      return;
    }
    if (_msg != null) setState(() => _msg = null);
  }

  Future<void> _submit() async {
    final handle = _name.text.trim();
    if (!validHandle(widget.source, handle)) return setState(() => _msg = 'Enter a valid new username.');
    final bad = _guard.check();
    if (bad != null) return setState(() => _msg = bad);
    setState(() {
      _busy = true;
      _msg = null;
    });
    final ask = (await s.chatProviders()).isEmpty ? null : s.askOnce;
    final r = await HandleChangeJudge(goalEngine(s).fetcher, ask)
        .judge(source: widget.source, oldHandle: widget.oldHandle, newHandle: handle, reason: _guard.text);
    final store = await GoalStore.of(s.library);
    if (r.outcome == ChangeOutcome.allowed) {
      final cfg = GoalConfig.parse(await store.latestGoalConfigJson());
      if (cfg != null) {
        final goals = [for (final g in cfg.goals) g.source == widget.source ? Goal(g.source, handle, g.target) : g];
        await store.saveGoalConfig(dateOf(DateTime.now()), GoalConfig(goals, cfg.blockApps).toJson());
      }
      await store.clearChange();
      Haptics.success();
      if (mounted) Navigator.pop(context, true);
      return;
    }
    if (r.outcome == ChangeOutcome.denied) {
      // A refusal starts the wait again: another day before the next try.
      await store.requestChange(dateOf(DateTime.now()));
      Haptics.warning();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = r.outcome == ChangeOutcome.denied ? 'Not accepted: ${r.message} You can try again after a day.' : r.message;
      if (r.outcome == ChangeOutcome.denied) _step = ChangeStep.wait;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final name = goalNames[widget.source]!.split(' ').first;
    final Widget body;
    if (_step == null) {
      body = const SizedBox();
    } else if (_step == ChangeStep.start) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Change your $name username?', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'A username is locked so a goal cannot be moved to an easier account. If you really need to change it, '
          'start here and come back tomorrow. If you still want to change it then, you will write at least ${ParagraphGuard.minWords} words '
          'about why, and the reason is checked.',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _ask, child: const Text('I want to change it')),
      ]);
    } else if (_step == ChangeStep.wait) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Come back tomorrow', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Your request is saved. If you still want to change the $name username tomorrow or later, open this page again.',
            style: t.textTheme.bodyMedium),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!, style: TextStyle(color: t.colorScheme.error))),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Why change it?', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Write at least ${ParagraphGuard.minWords} words in your own words, by hand: what happened to ${widget.oldHandle}. Pasting is not accepted. '
          'Your reason is sent to your own AI provider (with your key) to check it is a real reason, and is not saved by this app.',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autocorrect: false,
          maxLength: 40,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          decoration: InputDecoration(labelText: 'New $name username', counterText: ''),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          minLines: 6,
          maxLines: 12,
          onChanged: _changed,
          contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.editable(
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
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: t.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Check and change'),
        ),
      ]);
    }
    return LiquidScaffold(
      appBar: AppBar(title: const Text('Change username')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [body]),
    );
  }
}
