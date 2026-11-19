import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// Google Sign-In: gets an ID token that the backend verifies.
class GoogleAuth {
  GoogleAuth._();

  static Future<void>? _initialization;

  static bool get isConfigured => AppConfig.googleServerClientId.isNotEmpty;

  static Future<void> _ensureInitialized() {
    return _initialization ??= GoogleSignIn.instance
        .initialize(serverClientId: AppConfig.googleServerClientId)
        .catchError((Object error) {
      _initialization = null; // allow a retry next time
      throw error;
    });
  }

  /// Returns an ID token, or null when the user closes the Google window.
  static Future<String?> idToken() async {
    await _ensureInitialized();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('Google sign-in is not supported on this device.');
    }
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const <String>['email']);
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  static Future<void> signOut() async {
    if (_initialization == null) return;
    try {
      await _initialization;
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Not signed in with Google — nothing to do.
    }
  }
}
