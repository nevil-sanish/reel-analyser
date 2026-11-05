import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/export.dart';
import 'debug_screen.dart';
import 'liquid.dart';
import 'setup_screen.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  final AppServices services;
  const SettingsScreen(this.services, {super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppServices get s => widget.services;
  final _gemini = <TextEditingController>[];
  final _openai = TextEditingController();
  final _claude = TextEditingController();
  final _groq = TextEditingController();
  final _apify = TextEditingController();

  @override
  void initState() {
    super.initState();
    () async {
      final g = await s.keys.geminiKeys;
      _openai.text = await s.keys.openai ?? '';
      _claude.text = await s.keys.claude ?? '';
      _groq.text = await s.keys.groq ?? '';
      _apify.text = await s.keys.apify ?? '';
      if (!mounted) return;
      setState(() {
        _gemini.addAll([for (final k in g.isEmpty ? [''] : g) TextEditingController(text: k)]);
      });
    }();
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    await s.keys.setGeminiKeys([for (final c in _gemini) c.text]);
    await s.keys.setOpenai(_openai.text);
    await s.keys.setClaude(_claude.text);
    await s.keys.setGroq(_groq.text);
    await s.keys.setApify(_apify.text);
    if (mounted) _say('Keys saved on this phone');
  }

  Future<void> _export() async {
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
      final n = await importJson(s.library, utf8.decode(await f.readAsBytes()));
      if (mounted) _say('Imported $n new notes');
    } on FormatException catch (e) {
      if (mounted) _say('Could not import: ${e.message}');
    }
  }

  /// The one thing that leaves the phone on purpose: what you type here, as a GitHub issue you submit yourself.
  Future<void> _feedback() async {
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: text, maxLines: 5, autofocus: true, decoration: const InputDecoration(hintText: 'What works, what doesn\'t?')),
            const SizedBox(height: 8),
            const Text('Opens a GitHub issue with only this text and the app version. You review it before it\'s posted.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true || text.text.trim().isEmpty) return;
    final body = Uri.encodeQueryComponent('${text.text.trim()}\n\n— Reel Bot ${AppServices.version}');
    await s.bridge.openUrl('https://github.com/nevil-sanish/reel-brain/issues/new?title=Feedback&body=$body');
  }

  Widget _key(TextEditingController c, String label, {String? helper, Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: true,
          decoration: InputDecoration(labelText: label, helperText: helper, suffixIcon: trailing),
        ),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12), ...children],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LiquidScaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: const ListTile(
              leading: Icon(Icons.lock_rounded),
              title: Text('Everything stays on this phone'),
              subtitle: Text('No account, no server, no tracking. A reel you share goes only to the AI you picked, '
                  'with your key. Reels you watch are counted, never recorded. Feedback is the only thing you send us.'),
            ),
          ),
          const SizedBox(height: 16),
          _section('AI keys', [
            const Text('Gemini watches the whole video. Add several keys and each reel uses the next one.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            for (var i = 0; i < _gemini.length; i++)
              _key(_gemini[i], 'Gemini key ${i + 1}',
                  helper: i == 0 ? 'Free at aistudio.google.com → Get API key' : null,
                  trailing: _gemini.length > 1
                      ? IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => _gemini.removeAt(i)))
                      : null),
            TextButton.icon(
              onPressed: () => setState(() => _gemini.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Add another Gemini key'),
            ),
            const SizedBox(height: 8),
            _key(_openai, 'OpenAI key', helper: 'Optional. Used when Gemini can\'t: looks at 6 frames, no sound'),
            _key(_claude, 'Claude key', helper: 'Optional. Same as OpenAI: frames, no sound'),
            _key(_groq, 'Groq key', helper: 'Optional. Chat only'),
            _key(_apify, 'Apify token', helper: 'Optional. Only when Instagram won\'t give the video (~\$0.002 per reel)'),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Save keys'))),
          ]),
          _section('Appearance', [
            ValueListenableBuilder(
              valueListenable: Brand.mode,
              builder: (_, mode, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.dark_mode_rounded),
                title: const Text('Dark mode'),
                subtitle: const Text('Light is the default.'),
                value: mode == ThemeMode.dark,
                onChanged: (v) => Brand.mode.value = v ? ThemeMode.dark : ThemeMode.light,
              ),
            ),
          ]),
          _section('Counter', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Set up counting'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s))),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Counter debug'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebugScreen(s))),
            ),
          ]),
          _section('Backup', [
            const Text('Uninstalling deletes your notes. Export now and then.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.download), label: const Text('Export')),
              OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.upload), label: const Text('Import')),
            ]),
          ]),
          _section('Feedback', [
            const Text('Found a bug or have an idea?'),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: _feedback, icon: const Icon(Icons.feedback_outlined), label: const Text('Send feedback')),
          ]),
          Center(child: Text('Reel Bot ${AppServices.version}', style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
