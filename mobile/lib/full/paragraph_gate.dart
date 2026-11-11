import 'package:flutter/material.dart';

import '../ui/liquid.dart';
import 'blocker.dart';

/// Asks for a paragraph typed by hand: at least 50 words, no paste, not typed too fast, not written too quickly, no typical AI
/// wording. When those pass, [verify] (in practice [judgeParagraph] with the person's own AI key) decides whether it is a valid
/// reason and returns a message when it is not. Resolves true when it is accepted, false when the person backs out. Nothing is stored.
Future<bool> askParagraph(
  BuildContext context, {
  required String title,
  required String intro,
  required String action,
  required Future<String?> Function(String text) verify,
}) async =>
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _ParagraphScreen(title, intro, action, verify))) ?? false;

class _ParagraphScreen extends StatefulWidget {
  final String title, intro, action;
  final Future<String?> Function(String text) verify;
  const _ParagraphScreen(this.title, this.intro, this.action, this.verify);

  @override
  State<_ParagraphScreen> createState() => _ParagraphScreenState();
}

class _ParagraphScreenState extends State<_ParagraphScreen> {
  final _guard = ParagraphGuard();
  final _c = TextEditingController();
  String? _msg;
  bool _checking = false;

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
    if (_msg != null) setState(() => _msg = null);
  }

  Future<void> _go() async {
    final bad = _guard.check();
    if (bad != null) return setState(() => _msg = bad);
    setState(() => _checking = true);
    final refused = await widget.verify(_guard.text);
    if (!mounted) return;
    setState(() => _checking = false);
    if (refused != null) return setState(() => _msg = refused);
    if (mounted) Navigator.pop(context, true);
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
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: t.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _checking ? null : _go, child: Text(_checking ? 'Checking…' : widget.action)),
      ]),
    );
  }
}
