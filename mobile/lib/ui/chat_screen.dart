import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../pipeline/providers.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'liquid.dart';

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
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(c, (p, m.key));
                  },
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
    HapticFeedback.lightImpact();
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
    HapticFeedback.selectionClick(); // the answer landed
    setState(() {
      _turns.add(a.trim().isEmpty ? '(no answer)' : a.trim());
      _busy = false;
    });
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });

  String get _modelLabel => _provider == null
      ? ''
      : '${ChatModel.labels[_provider]} · ${ChatModel.models[_provider]![_model ?? ChatModel.models[_provider]!.keys.first]}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final chatting = _turns.isNotEmpty;
    const slide = Duration(milliseconds: 600);
    return LiquidScaffold(
      background: false,
      appBar: AppBar(
        title: AnimatedOpacity(opacity: chatting ? 1 : 0, duration: slide, child: const Text('Ask your reels')),
        actions: [
          if (chatting)
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(_turns.clear);
              },
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(widget.services)));
              _loadProviders();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Landing: a big title over the ask bar; it fades away once the first question is sent.
          IgnorePointer(
            ignoring: chatting,
            child: AnimatedOpacity(
              opacity: chatting ? 0 : 1,
              duration: slide,
              child: AnimatedSlide(
                offset: chatting ? const Offset(0, -0.1) : Offset.zero,
                duration: slide,
                curve: Curves.easeOutCubic,
                child: Align(
                  alignment: const Alignment(0, -0.6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const BrandMark(size: 64),
                      const SizedBox(height: 20),
                      ShaderMask(
                        shaderCallback: (r) => Brand.gradient.createShader(r),
                        child: Text('What did you\nlearn today?',
                            textAlign: TextAlign.center,
                            style: t.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -1)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _providers.isEmpty
                            ? 'Add a Gemini, OpenAI, Claude or Groq key in Settings to chat with your saved reels.'
                            : 'Ask anything. Answers come only from the reels you saved.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          if (chatting)
            Positioned.fill(
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(16, 8, 16, 120 + MediaQuery.paddingOf(context).bottom),
                itemCount: _turns.length + (_busy ? 1 : 0),
                itemBuilder: (_, i) => i == _turns.length
                    ? const Align(alignment: Alignment.centerLeft, child: _Typing())
                    : _Bubble(_turns[i], mine: i.isEven),
              ),
            ),
          // The ask bar: mid-screen and large at first, then it glides to the bottom and the chat takes over.
          AnimatedAlign(
            alignment: chatting ? Alignment.bottomCenter : const Alignment(0, 0.25),
            duration: slide,
            curve: Curves.easeOutCubic,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_provider != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ActionChip(
                        avatar: const Icon(Icons.auto_awesome, size: 16),
                        label: Text(_modelLabel, style: const TextStyle(fontSize: 12)),
                        onPressed: _pick,
                      ),
                    ),
                  Glass(
                    radius: 32,
                    padding: EdgeInsets.fromLTRB(20, chatting ? 4 : 12, 6, chatting ? 4 : 12),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: _providers.isNotEmpty,
                          minLines: 1,
                          maxLines: chatting ? 4 : 6,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          style: TextStyle(fontSize: chatting ? 16 : 18),
                          decoration: const InputDecoration(
                            hintText: 'Ask your saved reels…',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _busy ? null : _send,
                        child: AnimatedOpacity(
                          opacity: _busy ? 0.4 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  if (!chatting && _providers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final i in _ideas) ActionChip(label: Text(i), onPressed: () => _send(i))],
                      ),
                    ),
                ]),
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
            color: mine ? null : Brand.glass(Theme.of(context).brightness),
            border: mine ? null : Border.all(color: Brand.glassEdge(Theme.of(context).brightness)),
            borderRadius: BorderRadius.circular(22),
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
        decoration: BoxDecoration(color: Brand.glass(Theme.of(context).brightness), borderRadius: BorderRadius.circular(22)),
        child: const SizedBox(width: 24, height: 12, child: LinearProgressIndicator()),
      );
}
