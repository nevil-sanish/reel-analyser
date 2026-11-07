import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's own API keys, in the Android Keystore-backed secure storage. Never in the APK.
class KeyStore {
  // resetOnError: false. The plugin's default wipes every stored value whenever one read fails to decrypt (a
  // Keystore hiccup, two engines opening it at once), which is how a saved key could vanish. A failed read now
  // just reads as "not set" and nothing is deleted.
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

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
  Future<int> get updateCheckedAt async => int.tryParse(await _read('update_checked') ?? '') ?? 0;
  Future<void> setUpdateCheckedAt(int v) => _write('update_checked', '$v');

  Future<bool> get introSeen => flag('intro_seen');
  Future<void> setIntroSeen() => setFlag('intro_seen');

  /// One-time markers (intro shown, a migration done).
  Future<bool> flag(String k) async => await _read(k) != null;
  Future<void> setFlag(String k) => _write(k, '1');
  Future<void> setFlagTo(String k, bool on) => _write(k, on ? '1' : '');

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
