import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth error codes that mean the session itself is permanently unusable —
/// the server has already dropped it (revoked, rotated out, or malformed),
/// so retrying the same request will never succeed. When one of these
/// surfaces from any Supabase call, the right move is to stop trusting the
/// local session immediately rather than let every screen fail silently
/// until GoTrue's own background refresh eventually notices.
const Set<String> unrecoverableAuthErrorCodes = {
  'session_not_found',
  'refresh_token_not_found',
  'refresh_token_already_used',
  'bad_jwt',
};

/// Whether [error] is an [AuthApiException] carrying one of
/// [unrecoverableAuthErrorCodes].
bool isUnrecoverableAuthError(Object error) {
  return error is AuthApiException &&
      unrecoverableAuthErrorCodes.contains(error.code);
}

/// If [error] represents an unrecoverable session, sign out locally so the
/// app's auth gate (see `main.dart`'s `_AuthGate`, which listens to
/// `onAuthStateChange`) routes back to the pairing screen instead of the
/// current screen repeatedly failing against a session the server has
/// already dropped. No-ops for any other error.
///
/// Uses [SignOutScope.local]: this only clears the session on this device.
/// It does not (and cannot) fix a session shared across devices — that is
/// a backend pairing-flow issue, not something the client can correct.
Future<void> handleIfUnrecoverableAuthError(Object error) async {
  if (!isUnrecoverableAuthError(error)) return;
  final code = (error as AuthApiException).code;
  debugPrint('[Auth] 🧹 Unrecoverable session error ($code), signing out locally');
  try {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  } catch (e) {
    debugPrint('[Auth] ⚠️ Sign-out during error recovery failed: $e');
  }
}
