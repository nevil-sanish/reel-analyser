import 'package:flutter/material.dart';

import '../ui/liquid.dart';
import 'blocker.dart';

/// Asks for a paragraph typed by hand: at least 50 words, no paste, not typed too fast, not written too quickly, no typical AI
/// wording. The checks all run on the phone: the paragraph is not sent anywhere and not stored. Resolves true when it is accepted,
/// false when the person backs out.
Future<bool> askParagraph(
  BuildContext context, {
  required String title,
  required String intro,
  required String action,
}) async =>
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _ParagraphScreen(title, intro, action))) ?? false;

class _ParagraphScreen extends StatefulWidget {
  final String title, intro, action;
  const _ParagraphScreen(this.title, this.intro, this.action);

  @override
  State<_ParagraphScreen> createState() => _ParagraphScreenState();
}

class _ParagraphScreenState extends State<_ParagraphScreen> {
  final _guard = ParagraphGuard();
  final _c = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    final refused = _guard.accept(v, DateTime.now());
    if (refused != null) {
      _c.value = TextEditingValue(text: _guard.text, selection: TextSelection.collapsed(offset: _guard.text.length));
      setState(() => _msg = refused);
      return;
    }
    setState(() => _msg = null);
  }

  int get _words => _c.text.trim().isEmpty ? 0 : _c.text.trim().split(RegExp(r'\s+')).length;

  void _go() {
    final bad = _guard.check();
    if (bad != null) return setState(() => _msg = bad);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LiquidScaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        Text(widget.intro, style: t.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _c,
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
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (_words / ParagraphGuard.minWords).clamp(0, 1).toDouble()),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$_words / ${ParagraphGuard.minWords} words',
              style: t.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: _words >= ParagraphGuard.minWords ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant)),
        ]),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _msg == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  key: ValueKey(_msg),
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.colorScheme.error.withValues(alpha: 0.35)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: t.colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_msg!, style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w600))),
                  ]),
                ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _go,
          icon: const Icon(Icons.verified_outlined),
          label: Text(widget.action),
        ),
      ]),
    );
  }
}
