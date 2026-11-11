import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/models.dart';
import '../pipeline/providers.dart';
import 'chat_screen.dart';
import 'liquid.dart';
import 'motion.dart';
import 'theme.dart';

/// One saved chat thread and what it may know: a single note, or one folder's notes.
class ChatThread {
  final String title, heading, intro, shareSubject;
  final String? link;
  final bool brief;
  final List<String> starters;
  final Future<List<String>> Function() load;

  /// Saves the thread; an empty list removes it.
  final Future<void> Function(List<String> turns) save;

  /// The input box's hint.
  final String hint;
  final Future<String> Function(String provider, List<String> turns, String? model) ask;
  const ChatThread({
    required this.title,
    required this.heading,
    required this.intro,
    required this.shareSubject,
    this.link,
    this.brief = false,
    this.starters = const [],
    this.hint = 'Ask about this note…',
    required this.load,
    required this.save,
    required this.ask,
  });

  /// The chat bot of one analysis: the model is given nothing but this note.
  factory ChatThread.note(AppServices s, Reel reel) => ChatThread(
        title: 'Chat about this note',
        heading: reel.title,
        intro: 'Ask anything about this analysis. This chat only knows this note.',
        shareSubject: reel.title,
        link: reel.app == 'photo' ? null : reel.url,
        brief: true,
        starters: const ['What can I do with this?', 'Quote the key claims'],
        load: () => s.library.noteChat(reel.url),
        save: (t) => t.isEmpty ? s.library.deleteNoteChat(reel.url) : s.library.saveNoteChat(reel.url, t, DateTime.now().millisecondsSinceEpoch),
        ask: (p, t, m) => s.noteChat(p, reel, t, model: m),
      );

  /// A folder's own thread (id 0 = All): the model is given only that folder's notes.
  factory ChatThread.folder(AppServices s, int id, String name) => ChatThread(
        title: 'Chat · $name',
        heading: name,
        intro: 'Ask anything about the notes in this folder. This chat only knows them, and its thread is separate from every other folder.',
        shareSubject: 'Chat about $name',
        starters: const ['What are the main ideas here?', 'Make me a short study list', 'What should I try first?'],
        hint: id == 0 ? 'Ask about all your notes…' : 'Ask about $name…',
        load: () => s.library.folderChat(id),
        save: (t) => s.library.saveFolderChat(id, t, DateTime.now().millisecondsSinceEpoch),
        ask: (p, t, m) => s.folderChat(p, id, name, t, model: m),
      );
}

/// A chat screen over one [ChatThread]. The thread holds only this conversation.
class NoteChatScreen extends StatefulWidget {
  final AppServices services;
  final ChatThread thread;
  NoteChatScreen(this.services, Reel reel, {super.key}) : thread = ChatThread.note(services, reel);
  const NoteChatScreen.thread(this.services, this.thread, {super.key});

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
    final turns = await widget.thread.load();
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
          'Only the conversation is removed. The notes stay.',
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
    await widget.thread.save(const []);
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
      a = await widget.thread.ask(_provider!, sent, _model);
    } on Exception catch (e) {
      a = 'Couldn\'t answer: $e';
    }
    _turns.add(a.trim().isEmpty ? '(no answer)' : a.trim());
    // Saved even if the screen was closed while the answer was coming.
    await widget.thread.save(_turns);
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
        title: Text(widget.thread.title),
        actions: [
          if (_turns.isNotEmpty)
            IconButton(
              tooltip: 'Share this chat',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => s.bridge.shareText(
                [
                  'Chat about: ${widget.thread.heading}',
                  ?widget.thread.link,
                  for (final (i, m) in _turns.indexed) '\n${i.isEven ? 'Me' : 'Reel Analyser'}: ${boldSpans(m).toPlainText()}',
                ].join('\n'),
                subject: widget.thread.shareSubject,
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
                        widget.thread.heading,
                        style: t.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _providers.isEmpty
                            ? 'Add a Gemini, OpenAI, Claude or Groq key in Settings to chat.'
                            : widget.thread.intro,
                        style: t.textTheme.bodyLarge?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_providers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        if (widget.thread.brief) ...[
                          FilledButton.icon(
                            icon: const Icon(Icons.bolt_rounded),
                            label: const Text('Short & simple, nothing lost'),
                            onPressed: () => _send(kBriefLabel),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final i in widget.thread.starters)
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
                            if (_turns.isNotEmpty && widget.thread.brief)
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
                            decoration: InputDecoration(
                              hintText: widget.thread.hint,
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
