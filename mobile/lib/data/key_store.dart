import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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
      final tmp = File('${f.path}.$pid.tmp');
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
  static const _native = MethodChannel('reelbot/counter');
  static const _secret = {'gemini', 'openai', 'claude', 'groq', 'apify'};
  static const _sealed = 'enc1:';

  /// API keys are encrypted with a Keystore key of our own before they touch the file. If the phone's Keystore
  /// will not encrypt, the key is still saved (plain, in the private file) so typing a key never fails.
  Future<String> _seal(String v) async {
    try {
      return _sealed + (await _native.invokeMethod<String>('seal', {'text': v}))!;
    } on Object {
      return v;
    }
  }

  /// Null when a sealed value cannot be opened (the Keystore key is gone); the caller then reads "not set".
  Future<String?> _unseal(String v) async {
    if (!v.startsWith(_sealed)) return v;
    try {
      return await _native.invokeMethod<String>('unseal', {'text': v.substring(_sealed.length)});
    } on Object {
      readFailed = true;
      return null;
    }
  }
  static const _oldKeys = ['gemini', 'openai', 'claude', 'groq', 'apify', 'update_checked', 'intro_seen', 'legal_v1', 'dark', 'reduce_effects', 'retried_062'];

  Future<File> _flagFile() async => File(p.join(await getDatabasesPath(), 'reel_flags.json'));

  /// Writes are queued so two quick changes never read the same old file and drop one of them.
  static Future<void> _queue = Future.value();

  static Future<T> _serial<T>(Future<T> Function() job) {
    final done = _queue.then((_) => job());
    _queue = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  /// The app and the background task are separate engines sharing this file, so a read can catch it mid-swap. It is
  /// retried; if it still fails, a reader sees "nothing" but a writer ([strict]) throws instead of writing back an
  /// empty file over the keys.
  Future<Map<String, String>> _flags({bool strict = false}) async {
    Object? last;
    for (var i = 0; i < 4; i++) {
      try {
        final f = await _flagFile();
        if (!await f.exists()) return {};
        return {for (final e in (jsonDecode(await f.readAsString()) as Map).entries) '${e.key}': '${e.value}'};
      } on Object catch (e) {
        last = e;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
    if (!strict) return {};
    if (last is FormatException || last is TypeError) {
      // Really damaged, not mid-swap: keep it aside and start a fresh file.
      try {
        final f = await _flagFile();
        await f.rename('${f.path}.corrupt');
      } on Object {
        throw StateError('settings file unreadable: $last');
      }
      return {};
    }
    throw StateError('settings file unreadable: $last');
  }

  /// Once: copies whatever an older version kept in secure storage into the file. A broken Keystore just means
  /// nothing is copied; it is never asked again.
  Future<void> _migrate() async {
    try {
      if ((await _flags(strict: true)).containsKey(_migrated)) return;
    } on Object {
      return; // unreadable right now: do not mark the migration done or write anything
    }
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
    final sealedOld = {for (final e in old.entries) if (_secret.contains(e.key)) e.key: await _seal(e.value)};
    await _serial(() async {
      final all = await _flags(strict: true);
      if (all.containsKey(_migrated)) return;
      for (final e in old.entries) {
        all.putIfAbsent(e.key, () => _secret.contains(e.key) ? sealedOld[e.key]! : e.value);
      }
      all[_migrated] = '1';
      await _store(all);
    });
  }

  Future<void> _store(Map<String, String> all) async {
    final f = await _flagFile();
    final tmp = File('${f.path}.$pid.tmp');
    await tmp.writeAsString(jsonEncode(all), flush: true);
    await tmp.rename(f.path);
  }

  Future<String?> _readPlain(String k) async {
    await _migrate();
    final v = (await _flags())[k]?.trim();
    if (v == null || v.isEmpty) return null;
    if (!_secret.contains(k)) return v;
    final plain = await _unseal(v);
    if (plain != null && !v.startsWith(_sealed)) {
      final sealed = await _seal(plain); // a key saved before encryption existed is encrypted on its first read
      if (sealed.startsWith(_sealed)) {
        try {
          await _serial(() async => _store((await _flags(strict: true))..[k] = sealed));
        } on Object {
          // the key is still readable as it is; it is sealed on a later read
        }
      }
    }
    return plain == null || plain.isEmpty ? null : plain;
  }

  Future<void> _writePlain(String k, String v) async {
    await _migrate();
    final stored = _secret.contains(k) && v.isNotEmpty ? await _seal(v) : v;
    await _serial(() async {
      final all = await _flags(strict: true);
      all[k] = stored;
      await _store(all);
    });
  }

  Future<String?> _read(String k) => _readPlain(k);

  Future<void> _write(String k, String v) => _writePlain(k, v.trim());
}
