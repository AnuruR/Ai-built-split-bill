import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/receipt.dart';
import 'service_providers.dart';

/// All of the signed-in user's saved receipts, newest first (FR-12, FR-14).
/// Home and History both read this, so they always show the same data.
/// After saving, call `ref.invalidate(receiptsProvider)` to reload.
class ReceiptsNotifier extends AsyncNotifier<List<Receipt>> {
  @override
  Future<List<Receipt>> build() => ref.watch(receiptRepositoryProvider).fetchAll();

  Future<void> delete(String id) async {
    await ref.read(receiptRepositoryProvider).delete(id);
    state = AsyncData([...?state.value?.where((r) => r.id != id)]);
  }
}

final receiptsProvider =
    AsyncNotifierProvider<ReceiptsNotifier, List<Receipt>>(ReceiptsNotifier.new);
