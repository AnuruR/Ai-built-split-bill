import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth (FR-01), so screens don't talk to
/// Supabase directly and auth can be faked in tests.
///
/// Offline sign-in: Supabase keeps the session on the phone, but if the
/// app starts OFFLINE after the access token expired (~1 hour), the token
/// can't be refreshed and Supabase leaves `currentSession` empty – without
/// signing out. We then use the user id from the saved session
/// ("offline session") so the user still sees their cached data, and keep
/// retrying the refresh until the phone is online again.
class AuthService {
  final GoTrueClient _auth;

  /// Reads the session JSON that supabase_flutter saved on the phone.
  final Future<String?> Function() _readSavedSession;

  final _changes = StreamController<String?>.broadcast();
  late final StreamSubscription<AuthState> _sub;
  String? _offlineUserId;

  AuthService(this._auth, {Future<String?> Function()? readSavedSession})
    : _readSavedSession = readSavedSession ?? (() async => null) {
    _sub = _auth.onAuthStateChange.listen(
      (s) {
        // A real session (online again) or a sign-out ends offline mode.
        if (s.session != null || s.event == AuthChangeEvent.signedOut) {
          _offlineUserId = null;
        }
        _changes.add(currentUserId);
      },
      // Refresh failures while offline arrive as stream errors; they are
      // expected and must not crash the app.
      onError: (Object e) =>
          debugPrint('Auth refresh failed (probably offline): $e'),
    );
  }

  /// Call once at start-up, before the first screen.
  Future<void> init() async {
    if (_auth.currentSession != null) return;
    final raw = await _readSavedSession();
    if (raw == null) return;
    try {
      final user =
          (jsonDecode(raw) as Map<String, dynamic>)['user']
              as Map<String, dynamic>;
      _offlineUserId = user['id'] as String?;
    } catch (_) {
      // Unreadable saved session: treat as signed out.
    }
  }

  String? get currentUserId => _auth.currentUser?.id ?? _offlineUserId;
  bool get isSignedIn => _auth.currentSession != null || _offlineUserId != null;

  /// True when we are using the saved session because we are offline.
  bool get isOfflineSession =>
      _auth.currentSession == null && _offlineUserId != null;

  /// Emits the user id (or null) whenever the user signs in or out.
  Stream<String?> get userIdChanges => _changes.stream.distinct();

  /// When in an offline session, tries to restore the real session again.
  Future<void> retryRestore() async {
    if (!isOfflineSession) return;
    final raw = await _readSavedSession();
    if (raw == null) return;
    try {
      await _auth.recoverSession(raw); // success emits signedIn
    } catch (e) {
      // Still offline: keep the offline session. If the refresh token is
      // really invalid, Supabase emits signedOut and we go to Login.
      debugPrint('Session restore failed: $e');
    }
  }

  Future<void> signIn(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Returns true if the user is signed in straight away, false if Supabase
  /// requires them to confirm their email first.
  Future<bool> signUp(String name, String email, String password) async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': name.trim()}, // stored as user metadata
    );
    return res.session != null;
  }

  Future<void> signOut() async {
    _offlineUserId = null;
    try {
      await _auth.signOut();
    } catch (e) {
      // Offline: the server can't be told, but the phone forgets the session.
      await _auth.signOut(scope: SignOutScope.local);
    }
    _changes.add(null);
  }

  void dispose() {
    _sub.cancel();
    _changes.close();
  }
}

/// Turns Supabase/network errors into messages a user understands.
String friendlyError(Object e) {
  // Always log the raw error so the real cause is visible in the console.
  debugPrint('SnapSplit error: $e');

  if (e is SocketException || e is http.ClientException) {
    return "You're offline (can't reach the server). This needs an internet connection.";
  }
  // gotrue uses this ONE exception type for two different problems:
  if (e is AuthRetryableFetchException) {
    // 1) No status code: the request never got a response
    //    (offline, OR a wrong/misspelt SUPABASE_URL in env/dev.json).
    if (e.statusCode == null) {
      return "Can't reach the server. Check your internet connection and that "
          'SUPABASE_URL in env/dev.json is correct (https://<ref>.supabase.co).';
    }
    // 2) 5xx: the server answered with an error. On sign-up this is usually
    //    "Error sending confirmation email" (Supabase's built-in email is
    //    rate-limited); turning off "Confirm email" avoids it.
    final body = e.message.toLowerCase();
    if (body.contains('confirmation email') || body.contains('sending')) {
      return 'Supabase could not send the confirmation email (its free email '
          'service is rate-limited). Try later, or turn off "Confirm email" in '
          'Supabase → Authentication → Sign In / Providers → Email.';
    }
    return 'Server error (${e.statusCode}). Details: ${e.message}';
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'Wrong email or password.';
    if (m.contains('already registered')) {
      return 'An account with this email already exists.';
    }
    if (m.contains('not confirmed')) {
      return 'Please confirm your email first (check your inbox).';
    }
    if (m.contains('rate limit')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return e.message;
  }
  if (e is PostgrestException) {
    // PGRST205/PGRST202: the API can't find a table/function – the
    // database schema hasn't been created on this Supabase project.
    if (e.code == 'PGRST205' || e.code == 'PGRST202') {
      return 'The database is not set up yet. Run supabase/schema.sql in the '
          'Supabase SQL Editor, then tap Retry.';
    }
    if (e.code == '23505') return 'That name already exists.';
    return e.message;
  }
  return 'Something went wrong: $e';
}
