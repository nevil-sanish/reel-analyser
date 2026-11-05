import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../core/models.dart';
import '../native/counter_bridge.dart';
import '../pipeline/providers.dart';
import 'liquid.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// The home tab: today at a glance, then chat over saved notes. Every chat is saved and can be reopened.
class ChatScreen extends StatefulWidget {
  final AppServices services;

  /// Opens the Insights tab from the today strip.
  final VoidCallback? onInsights;
  const ChatScreen(this.services, {this.onInsights, super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  AppServices get s => widget.services;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  var _turns = <String>[]; // question, answer, question, ...
  int? _chatId;
  List<String> _providers = [];
  String? _provider;
  String? _model;
  bool _busy = false;
  DayTotal? _today;

  static const _ideas = ['What recipes have I saved?', 'Summarise my fitness reels', 'Tips I saved this week'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// Providers (a key may have been added in Settings) and today's counts.
  Future<void> _refresh() async {
    final p = await s.chatProviders();
    DayTotal? today;
    try {
      today = (await s.bridge.history(days: 1)).where((d) => d.date == localDate()).firstOrNull;
    } on Exception {
      today = null;
    }
    if (!mounted) return;
    setState(() {
      _providers = p;
      _today = today;
      if (!p.contains(_provider)) {
        _provider = p.firstOrNull;
        _model = null;
      }
    });
  }

  String get _modelLabel => _provider == null
      ? ''
      : '${ChatModel.labels[_provider]} · ${ChatModel.models[_provider]![_model ?? ChatModel.models[_provider]!.keys.first]}';

  Future<void> _pick() async {
    final picked = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
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
        ]),
      ),
    );
    if (picked == null) return;
    setState(() {
      _provider = picked.$1;
      _model = picked.$2;
    });
  }

  Future<void> _history() async {
    final chats = await s.library.chats();
    if (!mounted) return;
    final open = await showModalBottomSheet<(int, List<String>)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * 0.6,
          child: chats.isEmpty
              ? const Center(child: Text('No saved chats yet'))
              : StatefulBuilder(
                  builder: (c, set) => ListView(children: [
                    const Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Saved chats', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                    for (final ch in chats)
                      Dismissible(
                        key: ValueKey(ch.$1),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: Theme.of(c).colorScheme.error,
                          child: const Icon(Icons.delete_rounded, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          HapticFeedback.mediumImpact();
                          s.library.deleteChat(ch.$1);
                          set(() => chats.remove(ch));
                        },
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                          leading: const Icon(Icons.chat_bubble_outline_rounded),
                          title: Text(ch.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${ch.$4.length ~/ 2} questions · ${savedAgo(ch.$3, DateTime.now())}'),
                          onTap: () => Navigator.pop(c, (ch.$1, ch.$4)),
                        ),
                      ),
                  ]),
                ),
        ),
      ),
    );
    if (open == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _chatId = open.$1;
      _turns = [...open.$2];
    });
    _toEnd();
  }

  void _newChat() {
    HapticFeedback.selectionClick();
    setState(() {
      _turns = [];
      _chatId = null;
    });
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy || _provider == null) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() {
      _turns.add(q);
      _busy = true;
    });
    _toEnd();
    String a;
    try {
      // The last 10 turns are enough context and keep each request small.
      final recent = _turns.length > 10 ? _turns.sublist(_turns.length - 9) : _turns;
      a = await s.chat(_provider!, recent, model: _model);
    } on Exception catch (e) {
      a = 'Couldn\'t answer: $e';
    }
    if (!mounted) return;
    HapticFeedback.selectionClick(); // the answer landed
    setState(() {
      _turns.add(a.trim().isEmpty ? '(no answer)' : a.trim());
      _busy = false;
    });
    _chatId = await s.library.saveChat(_chatId, _turns, DateTime.now().millisecondsSinceEpoch);
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final chatting = _turns.isNotEmpty;
    const slide = Duration(milliseconds: 500);
    return LiquidScaffold(
      background: false,
      appBar: AppBar(
        title: const Text('Ask'),
        actions: [
          IconButton(tooltip: 'Saved chats', icon: const Icon(Icons.history_rounded), onPressed: _history),
          if (chatting) IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined), onPressed: _newChat),
          const ThemeToggle(),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(s)));
              _refresh();
            },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: slide,
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a), child: child),
            ),
            child: chatting
                ? ListView.builder(
                    key: ValueKey('chat$_chatId'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _turns.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) => i == _turns.length
                        ? const Align(alignment: Alignment.centerLeft, child: _Typing())
                        : _Bubble(_turns[i], mine: i.isEven),
                  )
                : ListView(
                    key: const ValueKey('landing'),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    children: [
                      _TodayStrip(_today, onTap: widget.onInsights),
                      const SizedBox(height: 40),
                      const Center(child: BrandMark(size: 64)),
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
                            : 'Ask anything. Answers come only from what you saved.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      if (_providers.isNotEmpty)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final i in _ideas) ActionChip(label: Text(i), onPressed: () => _send(i))],
                        ),
                    ],
                  ),
          ),
        ),
        // The ask bar always sits at the bottom, above the tab bar; the model chip rides on top of it.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_provider != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.auto_awesome, size: 16),
                      label: Text(_modelLabel, style: const TextStyle(fontSize: 12)),
                      onPressed: _pick,
                    ),
                  ),
                ),
              Glass(
                radius: 30,
                padding: const EdgeInsets.fromLTRB(20, 4, 6, 4),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: _providers.isNotEmpty,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
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
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Today at a glance on the Ask tab; tap for Insights.
class _TodayStrip extends StatelessWidget {
  final DayTotal? today;
  final VoidCallback? onTap;
  const _TodayStrip(this.today, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = today ?? DayTotal(localDate(), const {}, 0, 0);
    Widget stat(String v, String label) => Expanded(
          child: Column(children: [
            Text(v, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        );
    return GestureDetector(
      onTap: onTap,
      child: Glass(
        radius: 24,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(children: [
          stat('${d.reelsByApp['instagram'] ?? 0}', 'Reels today'),
          stat('${d.reelsByApp['youtube'] ?? 0}', 'Shorts today'),
          stat('${(d.ms / 60000).round()}m', 'Watching'),
          Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
        ]),
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
    final b = Theme.of(context).brightness;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child)),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          decoration: BoxDecoration(
            gradient: mine ? Brand.gradient : null,
            color: mine ? null : Brand.glass(b),
            border: mine ? null : Border.all(color: Brand.glassEdge(b)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(mine ? 22 : 6),
              bottomRight: Radius.circular(mine ? 6 : 22),
            ),
          ),
          child: SelectableText(text, style: TextStyle(color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface, height: 1.35)),
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Brand.glass(Theme.of(context).brightness), borderRadius: BorderRadius.circular(22)),
        child: const SizedBox(width: 28, height: 4, child: LinearProgressIndicator()),
      );
}
