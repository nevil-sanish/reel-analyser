import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/export.dart';
import '../data/key_backup.dart';
import '../data/key_store.dart';
import '../flavor.dart';
import 'debug_screen.dart';
import 'legal_screen.dart';
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

  /// Nothing is saved until the stored keys have been read: saving the still-empty boxes used to erase them.
  bool _loaded = false;
  String _saveNote = '';
  List<String> _lastGemini = const [];
  final _lastOther = <TextEditingController, String>{};
  Timer? _saveTimer;

  TextEditingController _watched(String text) => TextEditingController(text: text)..addListener(_changed);

  List<String> get _enteredGemini => [for (final c in _gemini) c.text.trim()].where((k) => k.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _applyStored();
  }

  /// Fills the key boxes from secure storage (at start, and after a backup restored keys).
  Future<void> _applyStored() async {
    final g = await s.keys.geminiKeys;
    final others = [await s.keys.openai ?? '', await s.keys.claude ?? '', await s.keys.groq ?? '', await s.keys.apify ?? ''];
    if (!mounted) return;
    setState(() {
      final first = !_loaded;
      for (final c in _gemini) {
        c.dispose();
      }
      _gemini
        ..clear()
        ..addAll([for (final k in g.isEmpty ? [''] : g) _watched(k)]);
      final boxes = [_openai, _claude, _groq, _apify];
      for (var i = 0; i < boxes.length; i++) {
        boxes[i].text = others[i];
        if (first) boxes[i].addListener(_changed);
      }
      _lastGemini = g;
      _lastOther
        ..clear()
        ..addAll({for (final c in boxes) c: c.text.trim()});
      _loaded = true;
      if (KeyStore.readFailed) {
        _saveNote = 'The phone could not read some saved keys, so nothing is changed automatically. '
            'Close and reopen the app; if this stays, enter the keys again.';
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_loaded) unawaited(_persist()); // leaving the screen never loses what was just typed
    super.dispose();
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Keys are saved as you type (a moment after you stop), so there is no Save button to forget.
  void _changed() {
    if (!_loaded || KeyStore.readFailed) return; // a failed read looks like an empty box: never save over it
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _persist);
  }

  /// Writes every key box to secure storage. Emptying the last Gemini box does not delete the saved keys;
  /// removing it with its minus button ([removeGemini]) does.
  Future<void> _persist({bool removeGemini = false}) async {
    if (KeyStore.readFailed) return;
    final entered = _enteredGemini;
    // Only the boxes that changed are written, so one key that failed to load is never overwritten by another edit.
    final writes = <Future<void> Function()>[
      if ((entered.isNotEmpty || removeGemini) && '$entered' != '$_lastGemini') () => s.keys.setGeminiKeys(entered),
      for (final (c, write) in [
        (_openai, s.keys.setOpenai),
        (_claude, s.keys.setClaude),
        (_groq, s.keys.setGroq),
        (_apify, s.keys.setApify),
      ])
        if (c.text.trim() != _lastOther[c]) () => write(c.text),
    ];
    if (writes.isEmpty) return;
    try {
      for (final w in writes) {
        await w();
      }
      if (entered.isNotEmpty || removeGemini) _lastGemini = entered;
      for (final c in _lastOther.keys) {
        _lastOther[c] = c.text.trim();
      }
      if (mounted) setState(() => _saveNote = 'Saved on this phone ✓');
    } on Object catch (e) {
      if (mounted) setState(() => _saveNote = 'Could not save the keys: $e');
    }
  }

  /// Whether the next Export also carries the API keys, encrypted with a passphrase.
  bool _withKeys = false;

  /// Asks for a passphrase; [confirm] asks twice (when choosing one). Null if cancelled.
  Future<String?> _askPassphrase({required bool confirm}) {
    final a = TextEditingController(), b = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(confirm ? 'Choose a passphrase' : 'Backup passphrase'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(confirm
                ? 'Your keys are encrypted with it. It is never stored; if you forget it, the keys in this backup cannot be opened.'
                : 'This backup has encrypted API keys. Enter the passphrase you chose when you exported it.'),
            const SizedBox(height: 12),
            TextField(controller: a, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Passphrase')),
            if (confirm) TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Again')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (confirm && a.text.length < 8) return set(() => error = 'Use at least 8 characters.');
                if (confirm && a.text != b.text) return set(() => error = 'The two do not match.');
                if (a.text.isEmpty) return set(() => error = 'Enter the passphrase.');
                Navigator.pop(c, a.text);
              },
              child: Text(confirm ? 'Encrypt' : 'Open'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    Map<String, Object?>? encrypted;
    if (_withKeys) {
      final pass = await _askPassphrase(confirm: true);
      if (pass == null) return;
      _say('Encrypting your keys; this can take up to 20 seconds…');
      final keys = await s.keys.all();
      encrypted = await Isolate.run(() => KeyBackup.encrypt(keys, pass));
    }
    final reels = await s.library.reels();
    final chats = await s.library.chats();
    await s.bridge.saveDownload('library.json', exportJson(reels, chats, encrypted));
    for (final r in reels) {
      await s.bridge.saveDownload(markdownName(r), r.toMarkdown());
    }
    if (mounted) _say('Exported ${reels.length} notes and ${chats.length} chats${encrypted == null ? '' : ', with your keys encrypted,'} to Downloads/ReelBot');
  }

  Future<void> _import() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (f == null) return;
    try {
      final text = utf8.decode(await f.readAsBytes());
      final (notes, chats) = await importJson(s.library, text);
      var restored = 0;
      final blob = encryptedKeysOf(text);
      while (blob != null && mounted) {
        final pass = await _askPassphrase(confirm: false);
        if (pass == null) break;
        try {
          restored = await s.keys.restore(await Isolate.run(() => KeyBackup.decrypt(blob, pass)));
          await _applyStored();
          break;
        } on WrongPassphrase {
          if (mounted) _say('That passphrase does not open this backup. Try again.');
        }
      }
      if (mounted) _say('Imported $notes new notes and $chats chats${restored > 0 ? ', and restored $restored keys' : ''}');
    } on FormatException catch (e) {
      if (mounted) _say('Could not import: ${e.message}');
    } on Object catch (e) {
      if (mounted) _say('Could not import: the file is not a Reel Analyser export ($e)');
    }
  }

  /// Settings → Erase all my data (Privacy Policy §7). Asks first; the app closes afterwards so nothing stale stays on screen.
  Future<void> _eraseAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Erase all your data?'),
        content: const Text('This deletes every note, chat, count, shared photo and API key from this phone. '
            'It cannot be undone. Files you exported to Downloads are not touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _saveTimer?.cancel();
    _loaded = false; // leaving this screen must not write the key boxes back
    try {
      await s.eraseEverything();
    } on Object catch (e) {
      if (mounted) _say('Could not erase everything: $e');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('All data erased'),
        content: const Text('Reel Analyser will close now.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    await SystemNavigator.pop();
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
    final body = Uri.encodeQueryComponent('${text.text.trim()}\n\n— Reel Analyser ${AppServices.version}');
    await s.bridge.openUrl('https://github.com/nevil-sanish/reel-analyser/issues/new?title=Feedback&body=$body');
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
                  trailing: IconButton(
                    tooltip: 'Remove this key',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      setState(() {
                        _gemini.removeAt(i);
                        if (_gemini.isEmpty) _gemini.add(_watched(''));
                      });
                      _persist(removeGemini: true);
                    },
                  )),
            TextButton.icon(
              onPressed: () => setState(() => _gemini.add(_watched(''))),
              icon: const Icon(Icons.add),
              label: const Text('Add another Gemini key'),
            ),
            const SizedBox(height: 8),
            _key(_openai, 'OpenAI key', helper: 'Optional. Used when Gemini can\'t: looks at 6 frames, no sound'),
            _key(_claude, 'Claude key', helper: 'Optional. Same as OpenAI: frames, no sound'),
            _key(_groq, 'Groq key', helper: 'Optional. Chat only'),
            _key(_apify, 'Apify token', helper: 'Optional. Only when Instagram won\'t give the video (~\$0.002 per reel)'),
            Text(_loaded ? (_saveNote.isEmpty ? 'Keys are saved on this phone as you type.' : _saveNote) : 'Loading your keys…',
                style: Theme.of(context).textTheme.bodySmall),
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
            ValueListenableBuilder(
              valueListenable: Brand.reduceEffects,
              builder: (_, reduced, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.blur_off_rounded),
                title: const Text('Reduce effects'),
                subtitle: const Text('A still background and no blur. Try it if scrolling stutters.'),
                value: reduced,
                onChanged: (v) => Brand.reduceEffects.value = v,
              ),
            ),
          ]),
          _section('Insights', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Set up Insights'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s))),
            ),
            if (!kPlayBuild)
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include my API keys'),
              subtitle: const Text('Encrypted with a passphrase you choose. The app decrypts them when you import this backup.'),
              value: _withKeys,
              onChanged: (v) => setState(() => _withKeys = v),
            ),
            const SizedBox(height: 4),
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
          _section('About and legal', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalScreen.privacy)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Terms of Use'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalScreen.terms)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: const Text('Open-source licenses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context, applicationName: 'Reel Analyser', applicationVersion: AppServices.version),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Erase all my data', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('Deletes every note, chat, count, photo and API key from this phone.'),
              onTap: _eraseAll,
            ),
          ]),
          Center(child: Text('Reel Analyser ${AppServices.version}', style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
