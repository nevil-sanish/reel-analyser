import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's own API keys, in the Android Keystore-backed secure storage. Never in the APK.
class KeyStore {
  static const _s = FlutterSecureStorage();

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

  /// Which Gemini key the next reel starts with.
  Future<int> get geminiTurn async => int.tryParse(await _read('gemini_turn') ?? '') ?? 0;
  Future<void> setGeminiTurn(int v) => _write('gemini_turn', '$v');

  Future<bool> get introSeen => flag('intro_seen');
  Future<void> setIntroSeen() => setFlag('intro_seen');

  /// One-time markers (intro shown, a migration done).
  Future<bool> flag(String k) async => await _read(k) != null;
  Future<void> setFlag(String k) => _write(k, '1');
  Future<void> setFlagTo(String k, bool on) => _write(k, on ? '1' : '');

  Future<String?> _read(String k) async {
    final v = (await _s.read(key: k))?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> _write(String k, String v) => v.trim().isEmpty ? _s.delete(key: k) : _s.write(key: k, value: v.trim());
}
