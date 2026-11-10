import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

/// The Supabase client (created in main.dart by Supabase.initialize).
final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Created and initialised in main.dart (it must read the saved session
/// before the first screen), then injected with overrideWithValue.
final authServiceProvider = Provider<AuthService>(
  (ref) => throw UnimplementedError('authServiceProvider is set up in main.dart'),
);

/// The signed-in user's id (null when signed out). Data providers watch
/// this, so when the user changes, their repositories are rebuilt and the
/// previous user's data is dropped from memory.
final currentUserIdProvider = StreamProvider<String?>((ref) async* {
  final auth = ref.watch(authServiceProvider);
  yield auth.currentUserId;
  yield* auth.userIdChanges;
});
