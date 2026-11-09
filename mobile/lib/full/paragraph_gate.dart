import 'package:flutter/material.dart';

import '../ui/liquid.dart';
import 'blocker.dart';

/// Asks for a paragraph typed by hand (at least 50 words, no paste, not too fast, no typical AI wording). Resolves true when it is
/// accepted, false when the person backs out. Nothing is sent anywhere or stored.
Future<bool> askParagraph(BuildContext context, {required String title, required String intro, required String action}) async =>
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
    if (!_guard.accept(v, DateTime.now())) {
      _c.value = TextEditingValue(text: _guard.text, selection: TextSelection.collapsed(offset: _guard.text.length));
      setState(() => _msg = "Pasted text isn't accepted. Type it yourself.");
      return;
    }
    if (_msg != null) setState(() => _msg = null);
  }

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
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: t.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _go, child: Text(widget.action)),
      ]),
    );
  }
}
