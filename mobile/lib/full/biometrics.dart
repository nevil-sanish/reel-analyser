import 'package:flutter/services.dart';

/// Fingerprint or face unlock for the app lock (full build only): Android's own prompt, through the native plugin.
abstract class Biometrics {
  /// Is there a fingerprint or face enrolled that the app can use?
  Future<bool> available();

  /// True when the person passed the prompt. False on cancel, failure or any error: the passcode is always the way in.
  Future<bool> check(String reason);
}

class NoBiometrics implements Biometrics {
  const NoBiometrics();
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> check(String reason) async => false;
}

class BridgeBiometrics implements Biometrics {
  static const _ch = MethodChannel('reelbot/counter');
  @override
  Future<bool> available() async {
    try {
      return await _ch.invokeMethod<bool>('biometricAvailable') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> check(String reason) async {
    try {
      return await _ch.invokeMethod<bool>('biometricCheck', {'reason': reason}) ?? false;
    } on Object {
      return false;
    }
  }
}
