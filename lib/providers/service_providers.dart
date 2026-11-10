import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store.dart';
import '../services/ocr_service.dart';
import '../services/offline_repositories.dart';
import '../services/receipt_repository.dart';
import '../services/supabase_repositories.dart';
import 'auth_provider.dart';

/// Services are exposed as providers so tests can swap in fakes
/// (`ProviderScope(overrides: [...])`). `onDispose` releases ML Kit.
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService();
  ref.onDispose(service.dispose);
  return service;
});

/// On-device storage for the offline cache.
final localStoreProvider = Provider<LocalStore>((ref) => SharedPrefsLocalStore());

/// Online/offline state and number of unsynced changes, for the banner.
class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    ref.watch(currentUserIdProvider); // reset when the user changes
    return const SyncStatus();
  }

  void update(SyncStatus Function(SyncStatus) change) => state = change(state);
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);

/// Offline-capable receipts, rebuilt per user.
final offlineReceiptRepositoryProvider = Provider<OfflineReceiptRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider).value ?? 'signed-out';
  return OfflineReceiptRepository(
    remote: SupabaseReceiptRepository(ref.watch(supabaseClientProvider)),
    store: ref.watch(localStoreProvider),
    userId: userId,
    onStatus: (change) => ref.read(syncStatusProvider.notifier).update(change),
  );
});

/// What the rest of the app uses. Tests override it with an in-memory one.
final receiptRepositoryProvider =
    Provider<ReceiptRepository>((ref) => ref.watch(offlineReceiptRepositoryProvider));
