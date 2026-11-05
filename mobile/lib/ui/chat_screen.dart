import 'package:flutter/material.dart';

import '../app_services.dart';
import '../pipeline/providers.dart';
import 'theme.dart';

/// Chat over every saved note, with whichever provider the user has a key for.
class ChatScreen extends StatefulWidget {
  final AppServices services;
  const ChatScreen(this.services, {super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <String>[]; // user, assistant, user, ...
  List<String> _providers = [];
  String? _provider;
  bool _busy = false;

  static const _ideas = ['What recipes have I saved?', 'Summarise my fitness reels', 'Which tips did I save this week?'];

  @override
  void initState() {
    super.initState();
    widget.services.chatProviders().then((p) {
      if (!mounted) return;
      setState(() {
        _providers = p;
        _provider = p.firstOrNull;
      });
    });
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
      a = await widget.services.chat(_provider!, recent);
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
        title: const Text('Ask your reels'),
        actions: [
          if (_providers.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButton<String>(
                value: _provider,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(16),
                items: [for (final p in _providers) DropdownMenuItem(value: p, child: Text(ChatModel.labels[p]!))],
                onChanged: (p) => setState(() => _provider = p),
              ),
            ),
        ],
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
