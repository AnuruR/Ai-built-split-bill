import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'config/env.dart';
import 'providers/auth_provider.dart';
import 'services/auth_service.dart';
import 'providers/router_provider.dart';

Future<void> main() async {
  // Needed before using plugins (Supabase stores the session on the device).
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  // Restores a saved session, so users stay signed in between launches.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseKey,
  );

  // supabase_flutter saves the session in SharedPreferences under this key.
  final sessionKey =
      'sb-${Uri.parse(Env.supabaseUrl).host.split('.').first}-auth-token';
  final auth = AuthService(
    Supabase.instance.client.auth,
    readSavedSession: () async =>
        (await SharedPreferences.getInstance()).getString(sessionKey),
  );
  await auth.init(); // enables offline sign-in with an expired token

  // ProviderScope stores the state of every Riverpod provider.
  runApp(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)],
      child: const SnapSplitApp(),
    ),
  );
}

const _seed = Color(0xFF00897B);

class SnapSplitApp extends ConsumerWidget {
  const SnapSplitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'SnapSplit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      // Follows the phone's light/dark setting.
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}

/// Shown when the app was started without --dart-define-from-file.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase is not configured.\n\n'
            'Copy env/dev.example.json to env/dev.json, fill in your project URL '
            'and key, then run:\n\nflutter run --dart-define-from-file=env/dev.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
