import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A session as supabase_flutter saves it on the phone, already EXPIRED.
String savedSession(String userId) => jsonEncode({
      'access_token': 'expired-token',
      'expires_in': 3600,
      'expires_at': 1, // 1970: long expired
      'refresh_token': 'refresh-token',
      'token_type': 'bearer',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-11-01T00:00:00Z',
      },
    });

void main() {
  // Port 9 on localhost: nothing listens there, so every request fails
  // like it would with no internet.
  GoTrueClient offlineClient() =>
      GoTrueClient(url: 'http://127.0.0.1:9/auth/v1', autoRefreshToken: false);

  test('no saved session: signed out', () async {
    final auth = AuthService(offlineClient());
    await auth.init();
    expect(auth.isSignedIn, isFalse);
    expect(auth.currentUserId, isNull);
  });

  test('expired saved session while offline: still signed in as that user', () async {
    final auth = AuthService(offlineClient(), readSavedSession: () async => savedSession('u-1'));
    await auth.init();
    expect(auth.isSignedIn, isTrue);
    expect(auth.isOfflineSession, isTrue);
    expect(auth.currentUserId, 'u-1'); // so the right user's cache is shown
  });

  test('retryRestore while still offline keeps the offline session', () async {
    final auth = AuthService(offlineClient(), readSavedSession: () async => savedSession('u-1'));
    await auth.init();
    await auth.retryRestore();
    expect(auth.isSignedIn, isTrue);
    expect(auth.currentUserId, 'u-1');
  });

  test('a corrupt saved session is treated as signed out', () async {
    final auth = AuthService(offlineClient(), readSavedSession: () async => '{not json');
    await auth.init();
    expect(auth.isSignedIn, isFalse);
  });

  test('signing out offline ends the offline session and notifies the router', () async {
    final auth = AuthService(offlineClient(), readSavedSession: () async => savedSession('u-1'));
    await auth.init();
    final emitted = <String?>[];
    final sub = auth.userIdChanges.listen(emitted.add);
    await auth.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(auth.isSignedIn, isFalse);
    expect(emitted, contains(null));
    await sub.cancel();
  });
}
