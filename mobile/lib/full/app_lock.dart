import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../data/key_store.dart';

/// Where the lock keeps its two small records. The real one is [KeyStore]'s private file; tests use a map.
abstract class LockStorage {
  Future<String?> readLock(String key);
  Future<void> writeLock(String key, String? value);
}

/// The passcode that opens the app (view only: sharing a reel to the app and the background analysis do not ask for it).
/// Only a salted PBKDF2 hash is stored, on the phone, and it never leaves it. Wrong tries slow down: after 5 in a row the next try
/// waits 30 seconds, then 1, 2, 4 minutes and so on, up to 15 minutes. If the passcode is forgotten there is no way back
/// in except clearing the app's data, which deletes the notes.
class AppLock {
  static const iterations = 60000;
  static const freeTries = 5;
  static final _pin = RegExp(r'^\d{4,8}$');
  static const _rec = 'app_lock';
  static const _st = 'app_lock_state';
  static const _bio = 'app_lock_bio';

  final LockStorage store;
  final DateTime Function() now;

  /// PBKDF2-HMAC-SHA256 of the passcode. The phone does it natively (about a twentieth of a second); tests use the Dart one.
  final Future<List<int>> Function(String pin, List<int> salt) hasher;
  AppLock(this.store, {DateTime Function()? now, Future<List<int>> Function(String, List<int>)? hasher})
      : now = now ?? DateTime.now,
        hasher = hasher ?? dartHash;

  static Future<List<int>> dartHash(String pin, List<int> salt) => Isolate.run(() => _hash(pin, salt));

  /// The same hash from Android's own PBKDF2; falls back to Dart if the call fails.
  static Future<List<int>> nativeHash(String pin, List<int> salt) async {
    try {
      final r = await const MethodChannel('reelbot/counter').invokeMethod<List<int>>('pbkdf2', {'pin': pin, 'salt': Uint8List.fromList(salt), 'iterations': iterations});
      if (r != null && r.length == 32) return r;
    } on Object {
      // fall through
    }
    return dartHash(pin, salt);
  }

  /// A message for a passcode that is not allowed, or null.
  static String? check(String pin) => _pin.hasMatch(pin) ? null : 'Use 4 to 8 digits.';

  Future<bool> get enabled async => ((await store.readLock(_rec)) ?? '').isNotEmpty;

  static Future<List<int>> _hash(String pin, List<int> salt) async =>
      (await (await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKeyFromPassword(password: pin, nonce: salt))
              .extractBytes());

  Future<void> set(String pin) async {
    final bad = check(pin);
    if (bad != null) throw FormatException(bad);
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final hash = await hasher(pin, salt);
    await store.writeLock(_rec, '1:${base64Encode(salt)}:${base64Encode(hash)}');
    await store.writeLock(_st, null);
  }

  /// Whether the lock screen also offers fingerprint or face.
  Future<bool> get biometric async => ((await store.readLock(_bio)) ?? '') == '1';

  Future<void> setBiometric(bool on) => store.writeLock(_bio, on ? '1' : null);

  Future<void> remove() async {
    await store.writeLock(_bio, null);
    await store.writeLock(_rec, null);
    await store.writeLock(_st, null);
  }

  /// How long until another try is allowed, or null.
  Future<Duration?> waitLeft() async {
    final s = ((await store.readLock(_st)) ?? '').split(',');
    if (s.length != 2) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(int.tryParse(s[1]) ?? 0);
    final left = until.difference(now());
    return left > Duration.zero ? left : null;
  }

  /// True when [pin] is right. While a wait is running it is false without looking at [pin].
  Future<bool> verify(String pin) async {
    if (await waitLeft() != null) return false;
    final rec = ((await store.readLock(_rec)) ?? '').split(':');
    if (rec.length != 3 || rec[0] != '1') return false;
    final salt = base64Decode(rec[1]), want = base64Decode(rec[2]);
    bool same(List<int> got) {
      var diff = got.length ^ want.length;
      for (var i = 0; i < got.length && i < want.length; i++) {
        diff |= got[i] ^ want[i];
      }
      return diff == 0;
    }

    // A wrong passcode also gets the Dart hash, so a record made by one hasher is never refused because another produced a different answer.
    if (same(await hasher(pin, salt)) || (hasher != dartHash && same(await dartHash(pin, salt)))) {
      await store.writeLock(_st, null);
      return true;
    }
    final fails = (int.tryParse(((await store.readLock(_st)) ?? '').split(',').first) ?? 0) + 1;
    final wait = fails < freeTries ? 0 : min(900, 30 * pow(2, fails - freeTries).toInt());
    await store.writeLock(_st, '$fails,${now().add(Duration(seconds: wait)).millisecondsSinceEpoch}');
    return false;
  }
}

/// The app's [KeyStore] as the lock's storage.
class KeyLockStorage implements LockStorage {
  final KeyStore keys;
  KeyLockStorage(this.keys);
  @override
  Future<String?> readLock(String key) => keys.readLock(key);
  @override
  Future<void> writeLock(String key, String? value) => keys.writeLock(key, value);
}
