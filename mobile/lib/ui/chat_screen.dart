import 'package:flutter/material.dart';

import '../app_services.dart';
import '../pipeline/providers.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// The home tab: chat over saved notes, with the provider and model the user picks.
class ChatScreen extends StatefulWidget {
  final AppServices services;
  const ChatScreen(this.services, {super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <String>[]; // user, assistant, user, ...
  List<String> _providers = [];
  String? _provider;
  String? _model;
  bool _busy = false;

  static const _ideas = ['What recipes have I saved?', 'Summarise my fitness reels', 'Which tips did I save this week?'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProviders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadProviders();
  }

  /// Re-read on resume and after Settings, so a newly added key shows up in the picker.
  Future<void> _loadProviders() async {
    final p = await widget.services.chatProviders();
    if (!mounted) return;
    setState(() {
      _providers = p;
      if (!p.contains(_provider)) {
        _provider = p.firstOrNull;
        _model = null;
      }
    });
  }

  Future<void> _pick() async {
    final picked = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in _providers) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text(ChatModel.labels[p]!, style: Theme.of(c).textTheme.titleSmall),
              ),
              for (final m in ChatModel.models[p]!.entries)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(m.value),
                  trailing: p == _provider && m.key == (_model ?? ChatModel.models[p]!.keys.first)
                      ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(c, (p, m.key)),
                ),
            ],
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _provider = picked.$1;
        _model = picked.$2;
      });
    }
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy || _provider == null) return;
    _input.clear();
    setState(() {
      _turns.add(q);
      _busy = true;
    });
    _toEnd();
    String a;
    try {
      // Last 10 turns are enough context and keep each request small.
      final recent = _turns.length > 10 ? _turns.sublist(_turns.length - 9) : _turns;
      a = await widget.services.chat(_provider!, recent, model: _model);
    } on Exception catch (e) {
      a = 'Couldn\'t answer: $e';
    }
    if (!mounted) return;
    setState(() {
      _turns.add(a.trim().isEmpty ? '(no answer)' : a.trim());
      _busy = false;
    });
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask your reels', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_turns.isNotEmpty)
            IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined), onPressed: () => setState(_turns.clear)),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(widget.services)));
              _loadProviders();
            },
          ),
        ],
        bottom: _provider == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: Text('${ChatModel.labels[_provider]} · ${ChatModel.models[_provider]![_model ?? ChatModel.models[_provider]!.keys.first]}'),
                    onPressed: _pick,
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 24),
                      const Center(child: BrandMark(size: 72)),
                      const SizedBox(height: 20),
                      Text(
                        _providers.isEmpty
                            ? 'Add a Gemini, OpenAI, Claude or Groq key in Settings to chat with your saved reels.'
                            : 'Ask anything about the reels you\'ve saved. Answers come only from your notes.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      if (_providers.isNotEmpty)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final i in _ideas) ActionChip(label: Text(i), onPressed: () => _send(i))],
                        ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _turns.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) => i == _turns.length
                        ? const Align(alignment: Alignment.centerLeft, child: _Typing())
                        : _Bubble(_turns[i], mine: i.isEven),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: _providers.isNotEmpty,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Ask your saved reels…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.arrow_upward_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  const _Bubble(this.text, {required this.mine});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          decoration: BoxDecoration(
            gradient: mine ? Brand.gradient : null,
            color: mine ? null : c.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SelectableText(text, style: TextStyle(color: mine ? Colors.white : c.onSurface)),
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(18)),
        child: const SizedBox(width: 24, height: 12, child: LinearProgressIndicator()),
      );
}
