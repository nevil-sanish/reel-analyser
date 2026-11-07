import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// The user's own API keys, in the Android Keystore-backed secure storage. Never in the APK.
class KeyStore {
  // resetOnError: false. The plugin's default wipes every stored value whenever one read fails to decrypt (a
  // Keystore hiccup, two engines opening it at once), which is how a saved key could vanish. A failed read now
  // just reads as "not set" and nothing is deleted.
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

  /// Erase all my data: every key, flag and counter this class holds.
  Future<void> eraseAll() async {
    await _s.deleteAll();
    final f = await _flagFile();
    if (await f.exists()) await f.delete();
  }

  /// Every key the user entered, as one map: what an encrypted backup holds.
  Future<Map<String, Object?>> all() async => {
        'gemini': await geminiKeys,
        'openai': await openai,
        'claude': await claude,
        'groq': await groq,
        'apify': await apify,
      };

  /// Puts back the keys of [all]. Only keys present in the backup are written; none is ever deleted.
  /// Returns how many keys were restored.
  Future<int> restore(Map<String, Object?> m) async {
    var n = 0;
    final gemini = [for (final k in (m['gemini'] as List?) ?? const []) '$k'.trim()].where((k) => k.isNotEmpty).toList();
    if (gemini.isNotEmpty) {
      await setGeminiKeys(gemini);
      n += gemini.length;
    }
    for (final (name, write) in [('openai', setOpenai), ('claude', setClaude), ('groq', setGroq), ('apify', setApify)]) {
      final v = '${m[name] ?? ''}'.trim();
      if (v.isNotEmpty) {
        await write(v);
        n++;
      }
    }
    return n;
  }

  /// True once a read threw, so Settings can say the key may still be there instead of showing an empty box.
  static bool readFailed = false;

  /// Several Gemini keys, one per line; the runner takes turns with them, one reel per key.
  Future<List<String>> get geminiKeys async =>
      (await _read('gemini') ?? '').split('\n').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
  Future<String?> get gemini async => (await geminiKeys).firstOrNull;
  Future<String?> get openai => _read('openai');
  Future<String?> get claude => _read('claude');
  Future<String?> get groq => _read('groq');
  Future<String?> get apify => _read('apify');

  Future<void> setGeminiKeys(List<String> v) => _write('gemini', v.map((k) => k.trim()).where((k) => k.isNotEmpty).join('\n'));
  Future<void> setOpenai(String v) => _write('openai', v);
  Future<void> setClaude(String v) => _write('claude', v);
  Future<void> setGroq(String v) => _write('groq', v);
  Future<void> setApify(String v) => _write('apify', v);

  /// When the update check last ran (GH-RELEASE-LATEST: at most once a day).
  Future<int> get updateCheckedAt async => int.tryParse(await _readPlain('update_checked') ?? '') ?? 0;
  Future<void> setUpdateCheckedAt(int v) => _writePlain('update_checked', '$v');

  Future<bool> get introSeen => flag('intro_seen');
  Future<void> setIntroSeen() => setFlag('intro_seen');

  /// One-time markers (intro shown, terms agreed, a migration done). They hold no secret, so they live in a plain
  /// file: a Keystore hiccup used to read them as "never set" and bring the intro and the terms back at every start.
  Future<bool> flag(String k) async => await _readPlain(k) == '1';
  Future<void> setFlag(String k) => _writePlain(k, '1');
  Future<void> setFlagTo(String k, bool on) => _writePlain(k, on ? '1' : '0');

  Future<File> _flagFile() async => File(p.join(await getDatabasesPath(), 'reel_flags.json'));

  Future<Map<String, String>> _flags() async {
    try {
      final f = await _flagFile();
      if (!await f.exists()) return {};
      return {for (final e in (jsonDecode(await f.readAsString()) as Map).entries) '${e.key}': '${e.value}'};
    } on Object {
      return {};
    }
  }

  /// The file first; a value an older version kept in secure storage is read once and copied over.
  Future<String?> _readPlain(String k) async {
    final v = (await _flags())[k];
    if (v != null) return v;
    final old = await _read(k);
    if (old != null) await _writePlain(k, old);
    return old;
  }

  Future<void> _writePlain(String k, String v) async {
    final all = await _flags();
    all[k] = v;
    final f = await _flagFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(all), flush: true);
    await tmp.rename(f.path);
  }

  Future<String?> _read(String k) async {
    for (var i = 0; i < 2; i++) {
      try {
        final v = (await _s.read(key: k))?.trim();
        return (v == null || v.isEmpty) ? null : v;
      } on Object {
        readFailed = true;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    return null;
  }

  Future<void> _write(String k, String v) => v.trim().isEmpty ? _s.delete(key: k) : _s.write(key: k, value: v.trim());
}
