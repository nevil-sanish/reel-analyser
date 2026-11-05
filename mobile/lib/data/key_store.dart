import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's own API keys, in the Android Keystore-backed secure storage. Never in the APK.
class KeyStore {
  static const _s = FlutterSecureStorage();

  Future<String?> get gemini => _read('gemini');
  Future<String?> get apify => _read('apify');

  Future<void> setGemini(String v) => _write('gemini', v);
  Future<void> setApify(String v) => _write('apify', v);

  Future<String?> _read(String k) async {
    final v = (await _s.read(key: k))?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> _write(String k, String v) => v.trim().isEmpty ? _s.delete(key: k) : _s.write(key: k, value: v.trim());
}
