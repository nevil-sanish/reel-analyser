import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class WrongPassphrase implements Exception {
  @override
  String toString() => 'That passphrase does not open this backup.';
}

/// The API keys inside a backup file: AES-256-GCM, with the key made from a passphrase you choose (PBKDF2-SHA256).
/// The passphrase is never stored, so the file is useless without it, and so is the app: only someone who
/// knows it can restore the keys. Forgetting it means entering the keys by hand again.
class KeyBackup {
  /// OWASP's figure for PBKDF2-SHA256. Backups made by v0.9.8 used 120,000 and still open: the accepted range
  /// is bounded so a forged file cannot make the phone grind for hours (too many) or weaken the key (too few).
  static const iterations = 600000;
  static const _minIterations = 100000, _maxIterations = 1000000;
  static final _aes = AesGcm.with256bits();

  static List<int> _random(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static Future<SecretKey> _derive(String passphrase, List<int> salt, int iter) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iter, bits: 256).deriveKeyFromPassword(password: passphrase, nonce: salt);

  /// [keys] is the plain map of every key the user entered (see `KeyStore.all`).
  static Future<Map<String, Object?>> encrypt(Map<String, Object?> keys, String passphrase) async {
    final salt = _random(16);
    final box = await _aes.encrypt(utf8.encode(jsonEncode(keys)), secretKey: await _derive(passphrase, salt, iterations));
    return {
      'v': 1,
      'kdf': 'pbkdf2-sha256',
      'iter': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  /// Throws [WrongPassphrase] for a wrong passphrase or a damaged file.
  static Future<Map<String, Object?>> decrypt(Map<String, Object?> blob, String passphrase) async {
    try {
      final iter = (blob['iter'] as num).toInt();
      if (iter < _minIterations || iter > _maxIterations) throw WrongPassphrase();
      final key = await _derive(passphrase, base64Decode('${blob['salt']}'), iter);
      final clear = await _aes.decrypt(
        SecretBox(base64Decode('${blob['ct']}'), nonce: base64Decode('${blob['nonce']}'), mac: Mac(base64Decode('${blob['mac']}'))),
        secretKey: key,
      );
      return Map<String, Object?>.from(jsonDecode(utf8.decode(clear)) as Map);
    } on Object {
      throw WrongPassphrase();
    }
  }
}
