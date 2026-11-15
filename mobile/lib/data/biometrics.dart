/// Fingerprint or face unlock for the app lock. Only the full build has one (Android's own prompt, through the native
/// plugin); the semi build uses [NoBiometrics], so it has neither the code nor the permission.
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
