import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regression tests: a server error on sign-up used to be shown as
/// "No internet connection".
void main() {
  test('no status code = could not reach server (offline or wrong URL)', () {
    final m = friendlyError(AuthRetryableFetchException(message: 'Failed host lookup'));
    expect(m, contains("Can't reach the server"));
    expect(m, contains('SUPABASE_URL'));
  });

  test('500 while sending the confirmation email is NOT a connection error', () {
    final m = friendlyError(AuthRetryableFetchException(
        message: '{"msg":"Error sending confirmation email"}', statusCode: '500'));
    expect(m, contains('confirmation email'));
    expect(m, isNot(contains("Can't reach")));
  });

  test('other server errors show the status and details', () {
    final m = friendlyError(AuthRetryableFetchException(message: 'boom', statusCode: '503'));
    expect(m, contains('503'));
    expect(m, contains('boom'));
  });

  test('SocketException', () {
    expect(friendlyError(const SocketException('x')), contains("offline"));
  });

  test('known auth messages', () {
    expect(friendlyError(const AuthException('Invalid login credentials')), 'Wrong email or password.');
    expect(friendlyError(const AuthException('User already registered')),
        'An account with this email already exists.');
  });

  test('missing table (schema not run) explains what to do', () {
    final m = friendlyError(const PostgrestException(message: 'not found', code: 'PGRST205'));
    expect(m, contains('schema.sql'));
  });
}
