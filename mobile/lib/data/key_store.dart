import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// The user's own API keys and the app's one-time flags. Never in the APK.
class KeyStore {
  // resetOnError: false. The plugin's default wipes every stored value whenever one read fails to decrypt (a
  // Keystore hiccup, two engines opening it at once), which is how a saved key could vanish. A failed read now
  // just reads as "not set" and nothing is deleted.
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

  /// Erase all my data: every key, flag and counter this class holds.
  Future<void> eraseAll() async {
    await _serial(() async {
      final f = await _flagFile();
      if (await f.exists()) await f.delete();
      final tmp = File('${f.path}.tmp');
      if (await tmp.exists()) await tmp.delete();
    });
    try {
      await _s.deleteAll();
    } on Object {
      // A broken Keystore holds nothing readable, and nothing reads it again.
    }
    await _serial(() async => _store({_migrated: '1'}));
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

  // ---- storage ----
  // Everything lives in one small JSON file in the app's private folder (no other app can read it, and backups are
  // off). The Android Keystore plugin is not used any more: on some phones it throws "Migration failed after
  // algorithm change" on every read and write, which is how saved keys vanished and could not be saved. Values an
  // older version kept there are copied over once ([_migrate]). An empty value in the file is a tombstone.

  static const _migrated = 'secure_migrated';
  static const _oldKeys = ['gemini', 'openai', 'claude', 'groq', 'apify', 'update_checked', 'intro_seen', 'legal_v1', 'dark', 'reduce_effects', 'retried_062'];

  Future<File> _flagFile() async => File(p.join(await getDatabasesPath(), 'reel_flags.json'));

  /// Writes are queued so two quick changes never read the same old file and drop one of them.
  static Future<void> _queue = Future.value();

  static Future<T> _serial<T>(Future<T> Function() job) {
    final done = _queue.then((_) => job());
    _queue = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  Future<Map<String, String>> _flags() async {
    try {
      final f = await _flagFile();
      if (!await f.exists()) return {};
      return {for (final e in (jsonDecode(await f.readAsString()) as Map).entries) '${e.key}': '${e.value}'};
    } on Object {
      return {};
    }
  }

  /// Once: copies whatever an older version kept in secure storage into the file. A broken Keystore just means
  /// nothing is copied; it is never asked again.
  Future<void> _migrate() async {
    if ((await _flags()).containsKey(_migrated)) return;
    final old = <String, String>{};
    for (final k in _oldKeys) {
      try {
        final v = (await _s.read(key: k))?.trim();
        if (v != null && v.isNotEmpty) old[k] = v;
      } on Object {
        readFailed = true;
        break; // every read fails the same way
      }
    }
    await _serial(() async {
      final all = await _flags();
      if (all.containsKey(_migrated)) return;
      for (final e in old.entries) {
        all.putIfAbsent(e.key, () => e.value);
      }
      all[_migrated] = '1';
      await _store(all);
    });
  }

  Future<void> _store(Map<String, String> all) async {
    final f = await _flagFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(all), flush: true);
    await tmp.rename(f.path);
  }

  Future<String?> _readPlain(String k) async {
    await _migrate();
    final v = (await _flags())[k];
    return v == null || v.trim().isEmpty ? null : v.trim();
  }

  Future<void> _writePlain(String k, String v) async {
    await _migrate();
    await _serial(() async {
      final all = await _flags();
      all[k] = v;
      await _store(all);
    });
  }

  Future<String?> _read(String k) => _readPlain(k);

  Future<void> _write(String k, String v) => _writePlain(k, v.trim());
}
