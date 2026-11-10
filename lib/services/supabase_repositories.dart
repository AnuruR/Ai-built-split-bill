import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'people_repository.dart';
import 'receipt_mapper.dart';
import 'receipt_repository.dart';

/// Thrown when deleting a person who appears on a saved receipt.
class PersonInUseException implements Exception {
  @override
  String toString() =>
      'This person is on saved receipts, so they can\'t be removed (it would change old splits).';
}

/// People stored in Supabase. user_id is filled by the database default
/// (auth.uid()) and RLS makes sure we only ever see our own rows.
class SupabasePeopleRepository implements PeopleRepository {
  final SupabaseClient _db;
  SupabasePeopleRepository(this._db);

  @override
  Future<List<Person>> fetchAll() async {
    var rows = await _db.from('people').select('id, name').order('created_at');
    if (rows.isEmpty) {
      // First use: create "Me" so the user can include themselves.
      rows = [await _db.from('people').insert({'name': 'Me'}).select('id, name').single()];
    }
    return rows.map(Person.fromMap).toList();
  }

  @override
  Future<Person> add(String name) async =>
      Person.fromMap(await _db.from('people').insert({'name': name}).select('id, name').single());

  @override
  Future<void> rename(String id, String name) =>
      _db.from('people').update({'name': name}).eq('id', id);

  @override
  Future<void> delete(String id) async {
    try {
      await _db.from('people').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') throw PersonInUseException(); // foreign key RESTRICT
      rethrow;
    }
  }
}

class SupabaseReceiptRepository implements ReceiptRepository {
  final SupabaseClient _db;
  SupabaseReceiptRepository(this._db);

  // One request fetches receipts with their items and assignments
  // (PostgREST "embedding" follows the foreign keys).
  static const _select = '*, items(*, assignments(*))';

  @override
  Future<List<Receipt>> fetchAll() async {
    final rows = await _db
        .from('receipts')
        .select(_select)
        .order('receipt_date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(ReceiptMapper.fromRow).toList();
  }

  @override
  Future<Receipt?> fetchById(String id) async {
    final row = await _db.from('receipts').select(_select).eq('id', id).maybeSingle();
    return row == null ? null : ReceiptMapper.fromRow(row);
  }

  /// Calls the save_receipt SQL function: one transaction, all or nothing.
  @override
  Future<void> save(Receipt receipt) =>
      _db.rpc('save_receipt', params: {'p': ReceiptMapper.toPayload(receipt)});

  @override
  Future<void> delete(String id) => _db.from('receipts').delete().eq('id', id);
}
