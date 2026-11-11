import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/models.dart';
import '../pipeline/providers.dart';
import 'chat_screen.dart';
import 'liquid.dart';
import 'motion.dart';
import 'theme.dart';

/// The chat bot of one analysis. Its thread is saved with the note and holds only this conversation;
/// the model is given nothing but this note.
class NoteChatScreen extends StatefulWidget {
  final AppServices services;
  final Reel reel;
  const NoteChatScreen(this.services, this.reel, {super.key});

  @override
  State<NoteChatScreen> createState() => _NoteChatScreenState();
}

/// The preload: one tap asks for the whole note in short, simple words with nothing left out.
/// What the thread shows for the preload; [kBriefPrompt] is what the model receives.
const kBriefLabel = 'Short & simple';
const kBriefPrompt =
    'Rewrite this whole note in short, simple words. Keep every fact, number, name, step and tip; '
    'leave nothing out and add nothing. Use short bullet lines.';

class _NoteChatScreenState extends State<NoteChatScreen> {
  AppServices get s => widget.services;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  var _turns = <String>[];
  List<String> _providers = [];
  String? _provider;
  String? _model;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final turns = await s.library.noteChat(widget.reel.url);
    final p = await s.chatProviders();
    if (!mounted) return;
    setState(() {
      _turns = turns;
      _providers = p;
      _provider = p.firstOrNull;
      _loaded = true;
    });
    _toEnd();
  }

  String get _modelLabel =>
      '${ChatModel.labels[_provider]} · ${ChatModel.models[_provider]![_model ?? ChatModel.models[_provider]!.keys.first]}';

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
                child: Text(
                  ChatModel.labels[p]!,
                  style: Theme.of(c).textTheme.titleSmall,
                ),
              ),
              for (final m in ChatModel.models[p]!.entries)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(m.value),
                  trailing:
                      p == _provider &&
                          m.key == (_model ?? ChatModel.models[p]!.keys.first)
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(c).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    Haptics.select();
                    Navigator.pop(c, (p, m.key));
                  },
                ),
            ],
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _provider = picked.$1;
      _model = picked.$2;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text(
          'Only the conversation is removed. The note stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await s.library.deleteNoteChat(widget.reel.url);
    if (mounted) setState(() => _turns = []);
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy || _provider == null) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    Haptics.light();
    setState(() {
      _turns.add(q);
      _busy = true;
    });
    _toEnd();
    String a;
    try {
      final recent = _turns.length > 10
          ? _turns.sublist(_turns.length - 9)
          : _turns;
      final sent = [
        for (final t in recent) t == kBriefLabel ? kBriefPrompt : t,
      ];
      a = await s.noteChat(_provider!, widget.reel, sent, model: _model);
    } on Exception catch (e) {
      a = 'Couldn\'t answer: $e';
    }
    _turns.add(a.trim().isEmpty ? '(no answer)' : a.trim());
    // Saved even if the screen was closed while the answer was coming.
    await s.library.saveNoteChat(
      widget.reel.url,
      _turns,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    Haptics.select();
    setState(() => _busy = false);
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LiquidScaffold(
      appBar: AppBar(
        title: const Text('Chat about this note'),
        actions: [
          if (_turns.isNotEmpty)
            IconButton(
              tooltip: 'Share this chat',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => s.bridge.shareText(
                [
                  'Chat about: ${widget.reel.title}',
                  if (widget.reel.app != 'photo') widget.reel.url,
                  for (final (i, m) in _turns.indexed) '\n${i.isEven ? 'Me' : 'Reel Analyser'}: $m',
                ].join('\n'),
                subject: widget.reel.title,
              ),
            ),
          if (_turns.isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clear,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: !_loaded
                ? const SizedBox()
                : _turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    children: [
                      Text(
                        widget.reel.title,
                        style: t.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _providers.isEmpty
                            ? 'Add a Gemini, OpenAI, Claude or Groq key in Settings to chat about this note.'
                            : 'Ask anything about this analysis. This chat only knows this note.',
                        style: t.textTheme.bodyLarge?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_providers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          icon: const Icon(Icons.bolt_rounded),
                          label: const Text('Short & simple, nothing lost'),
                          onPressed: () => _send(kBriefLabel),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final i in const [
                              'What can I do with this?',
                              'Quote the key claims',
                            ])
                              ActionChip(
                                label: Text(i),
                                onPressed: () => _send(i),
                              ),
                          ],
                        ),
                      ],
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _turns.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) => i == _turns.length
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: ChatTyping(),
                          )
                        : ChatBubble(_turns[i], mine: i.isEven),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_provider != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (_turns.isNotEmpty)
                              ActionChip(
                                avatar: const Icon(
                                  Icons.bolt_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Short & simple',
                                  style: TextStyle(fontSize: 12),
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _send(kBriefLabel),
                              ),
                            ActionChip(
                              avatar: const Icon(Icons.auto_awesome, size: 16),
                              label: Text(
                                _modelLabel,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: _pick,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Glass(
                    radius: 30,
                    padding: const EdgeInsets.fromLTRB(20, 4, 6, 4),
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
                            decoration: const InputDecoration(
                              hintText: 'Ask about this note…',
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
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                gradient: Brand.gradient,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                color: Brand.onGold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
