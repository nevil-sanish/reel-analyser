import 'package:flutter/material.dart';

import '../app_services.dart';

class AskScreen extends StatefulWidget {
  final AppServices services;
  const AskScreen(this.services, {super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _q = TextEditingController();
  String _answer = '';
  bool _busy = false;

  Future<void> _ask() async {
    if (_q.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _answer = '';
    });
    String a;
    try {
      a = await widget.services.ask(_q.text.trim());
    } on Exception catch (e) {
      a = 'Something went wrong: $e';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _answer = a;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask your library')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(
              hintText: 'e.g. What were the high-protein breakfast ideas?',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _ask),
            ),
          ),
          const SizedBox(height: 16),
          if (_busy) const Center(child: CircularProgressIndicator()),
          SelectableText(_answer),
        ],
      ),
    );
  }
}
