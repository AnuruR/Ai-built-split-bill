import '../models/receipt.dart';

/// Where saved receipts live (FR-14). Same idea as PeopleRepository:
/// in memory for now, Supabase in Phase 7, without changing the screens.
abstract interface class ReceiptRepository {
  /// Newest first.
  Future<List<Receipt>> fetchAll();
  Future<Receipt?> fetchById(String id);

  /// Inserts or updates (same id = update), including items and assignments.
  Future<void> save(Receipt receipt);
  Future<void> delete(String id);
}

class InMemoryReceiptRepository implements ReceiptRepository {
  final Map<String, Receipt> _byId = {};

  @override
  Future<List<Receipt>> fetchAll() async =>
      _byId.values.toList()..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<Receipt?> fetchById(String id) async => _byId[id];

  @override
  Future<void> save(Receipt receipt) async => _byId[receipt.id] = receipt;

  @override
  Future<void> delete(String id) async => _byId.remove(id);
}
