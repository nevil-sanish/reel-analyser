import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/export.dart';

class SettingsScreen extends StatefulWidget {
  final AppServices services;
  const SettingsScreen(this.services, {super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gemini = TextEditingController();
  final _apify = TextEditingController();
  bool _autoSave = false;

  @override
  void initState() {
    super.initState();
    () async {
      _gemini.text = await widget.services.keys.gemini ?? '';
      _apify.text = await widget.services.keys.apify ?? '';
      final s = await widget.services.bridge.status();
      if (mounted) setState(() => _autoSave = s.autoSave);
    }();
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    await widget.services.keys.setGemini(_gemini.text);
    await widget.services.keys.setApify(_apify.text);
    if (mounted) _say('Keys saved on this phone');
  }

  Future<void> _export() async {
    final s = widget.services;
    final reels = await s.library.reels();
    await s.bridge.saveDownload('library.json', exportJson(reels));
    for (final r in reels) {
      await s.bridge.saveDownload(markdownName(r), r.toMarkdown());
    }
    if (mounted) _say('Exported ${reels.length} notes to Downloads/ReelBot');
  }

  Future<void> _import() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (f == null) return;
    try {
      final n = await importJson(widget.services.library, utf8.decode(await f.readAsBytes()));
      if (mounted) _say('Imported $n new notes');
    } on FormatException catch (e) {
      if (mounted) _say('Could not import: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Reel Bot uses your own keys. They stay on this phone; there is no Reel Bot server.'),
          const SizedBox(height: 16),
          TextField(
            controller: _gemini,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Gemini API key',
              helperText: 'Free at aistudio.google.com → Get API key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apify,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Apify API token (optional)',
              helperText: 'Only used when Instagram won\'t give the video (~\$0.002 per reel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save keys')),
          const Divider(height: 40),
          Text('Backup', style: Theme.of(context).textTheme.titleMedium),
          const Text('Uninstalling the app deletes the library. Export it now and then.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.download), label: const Text('Export to Downloads/ReelBot')),
          OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.upload), label: const Text('Import library.json')),
          const Divider(height: 40),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-Save (experimental)'),
            subtitle: const Text('The bubble\'s Save presses Share → Reel Bot for you. If it misses, it goes back and asks '
                'you to share by hand. Off: Save only asks you to share.'),
            value: _autoSave,
            onChanged: (v) async {
              await widget.services.bridge.setAutoSave(v);
              setState(() => _autoSave = v);
            },
          ),
        ],
      ),
    );
  }
}
