import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firebase Auth diagnostics.
///
/// The app uses this helper only for safe debug information: uid, email,
/// providerData and isAnonymous. It never prints passwords or ID tokens.
class AuthDebug {
  const AuthDebug._();

  /// Formats providerData so we can see which sign-in provider owns the session.
  static String describeProviderData(User? user) {
    if (user == null || user.providerData.isEmpty) {
      return '[]';
    }

    return user.providerData
        .map(
          (info) => '{providerId=${info.providerId}, uid=${info.uid}, '
              'email=${info.email ?? ''}}',
        )
        .join(', ');
  }

  /// Formats the current Firebase user without exposing sensitive credentials.
  static String describeUser(User? user) {
    if (user == null) {
      return 'null';
    }

    return 'uid=${user.uid}, email=${user.email ?? ''}, '
        'isAnonymous=${user.isAnonymous}, '
        'providerData=${describeProviderData(user)}';
  }

  /// Prints a user diagnostic line with a stable [AUTH] prefix.
  static void logUser(String source, User? user) {
    debugPrint('[AUTH][$source] currentUser=${describeUser(user)}');
  }

  /// Detects the Firebase invalid refresh token family of errors.
  ///
  /// Firebase may expose this as a FirebaseAuthException, a generic
  /// FirebaseException, or a platform error text that contains
  /// INVALID_REFRESH_TOKEN. We check code, message and toString() defensively.
  static bool isInvalidRefreshTokenError(Object error) {
    final parts = <String>[error.toString()];

    if (error is FirebaseAuthException) {
      parts
        ..add(error.code)
        ..add(error.message ?? '');
    } else if (error is FirebaseException) {
      parts
        ..add(error.code)
        ..add(error.message ?? '');
    }

    final normalized = parts.join(' ').toUpperCase();
    return normalized.contains('INVALID_REFRESH_TOKEN') ||
        normalized.contains('TOKEN_EXPIRED') ||
        normalized.contains('USER_TOKEN_EXPIRED');
  }

  /// Signs out from a broken local session if the error is INVALID_REFRESH_TOKEN.
  ///
  /// A bad refresh token cannot be repaired by retrying the same request. The
  /// safest local recovery is to clear the Firebase Auth session and let
  /// authStateChanges return the app to AuthScreen.
  static Future<bool> signOutIfInvalidRefreshToken(
    Object error, {
    required String source,
  }) async {
    if (!isInvalidRefreshTokenError(error)) {
      return false;
    }

    debugPrint(
      '[AUTH][$source] Invalid refresh token detected: $error',
    );
    await FirebaseAuth.instance.signOut();
    debugPrint('[AUTH] Invalid refresh token. User signed out.');
    return true;
  }

  /// Validates that the current Firebase user can still produce an ID token.
  ///
  /// This method is useful at app startup and immediately before Firestore
  /// writes. If Firebase throws INVALID_REFRESH_TOKEN, we automatically sign out
  /// and return null.
  static Future<User?> validateCurrentUserToken({
    required String source,
    bool forceRefresh = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    logUser('$source before token validation', user);

    if (user == null) {
      return null;
    }

    try {
      final token = await user.getIdToken(forceRefresh);
      debugPrint(
        '[AUTH][$source] ID token validation succeeded. '
        'forceRefresh=$forceRefresh hasToken=${token != null && token.isNotEmpty}',
      );
      return FirebaseAuth.instance.currentUser;
    } catch (error) {
      final signedOut = await signOutIfInvalidRefreshToken(
        error,
        source: source,
      );

      if (signedOut) {
        return null;
      }

      debugPrint('[AUTH][$source] ID token validation failed: $error');
      return FirebaseAuth.instance.currentUser;
    }
  }
}
