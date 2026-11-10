import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'people_provider.dart';
import 'receipts_provider.dart';
import 'service_providers.dart';

/// Retries syncing while offline or while changes are waiting:
/// every 30 seconds, and whenever the app comes back to the foreground.
/// Reloading receiptsProvider runs fetchAll(), which first flushes the
/// outbox, so "retry" is simply "reload".
///
/// Watched by the Home screen, so it runs while the user is signed in.
final syncControllerProvider = Provider<void>((ref) {
  Future<void> retry() async {
    // Offline session (expired token, started offline): restore it first.
    await ref.read(authServiceProvider).retryRestore();
    final s = ref.read(syncStatusProvider);
    if (!s.offline && s.pending == 0) return;
    ref.invalidate(receiptsProvider);
    if (s.offline) ref.invalidate(peopleProvider);
  }

  final timer = Timer.periodic(const Duration(seconds: 30), (_) => retry());
  final lifecycle = AppLifecycleListener(onResume: retry);
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
  });
});
