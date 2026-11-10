import 'dart:convert';

import '../models/models.dart';
import 'local_store.dart';
import 'network_errors.dart';
import 'people_repository.dart';
import 'receipt_mapper.dart';
import 'receipt_repository.dart';

/// What the UI shows in the sync banner.
class SyncStatus {
  /// The last request could not reach the server.
  final bool offline;

  /// Receipt changes saved on the phone but not yet on the server.
  final int pending;

  /// A queued change the server rejected (it was discarded).
  final String? lastError;

  const SyncStatus({this.offline = false, this.pending = 0, this.lastError});

  SyncStatus copyWith({bool? offline, int? pending, String? Function()? lastError}) => SyncStatus(
        offline: offline ?? this.offline,
        pending: pending ?? this.pending,
        lastError: lastError == null ? this.lastError : lastError(),
      );
}

/// Offline-capable receipts: wraps the Supabase repository (the "remote")
/// and keeps a copy on the phone. (This wrapping is the Decorator pattern:
/// same interface, extra behaviour.)
///
///  * Reads: try the server and refresh the cache; if offline, use the cache.
///  * Writes: try the server; if offline, apply to the cache and put the
///    change in an OUTBOX, which is sent later in order.
///
/// Why this is safe: receipt ids are generated on the phone, and
/// save_receipt REPLACES a receipt with the same id, so sending a queued
/// save twice gives the same result (it is "idempotent").
class OfflineReceiptRepository implements ReceiptRepository {
  final ReceiptRepository remote;
  final LocalStore store;
  final String userId;
  final void Function(SyncStatus Function(SyncStatus)) onStatus;

  OfflineReceiptRepository({
    required this.remote,
    required this.store,
    required this.userId,
    required this.onStatus,
  });

  Future<void>? _flushing; // so two syncs never run at the same time

  // ---------- public API ----------

  @override
  Future<List<Receipt>> fetchAll() async {
    await flush();
    try {
      final fromServer = await remote.fetchAll();
      // Anything still queued (e.g. flush failed midway) overrides the server.
      final merged = _applyOutbox(fromServer, await _readOutbox());
      await _writeCache(merged);
      onStatus((s) => s.copyWith(offline: false));
      return merged;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      onStatus((s) => s.copyWith(offline: true));
      return _readCache();
    }
  }

  @override
  Future<Receipt?> fetchById(String id) async =>
      (await fetchAll()).where((r) => r.id == id).firstOrNull;

  @override
  Future<void> save(Receipt receipt) async {
    await flush(); // send older queued changes first, to keep the order
    try {
      await remote.save(receipt);
    } catch (e) {
      if (!isNetworkError(e)) rethrow; // real error: show it, don't queue
      await _enqueue({'op': 'save', 'id': receipt.id, 'receipt': ReceiptMapper.toPayload(receipt)});
      onStatus((s) => s.copyWith(offline: true));
    }
    final cache = await _readCache();
    await _writeCache(_upsert(cache, receipt));
  }

  @override
  Future<void> delete(String id) async {
    await flush();
    try {
      await remote.delete(id);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await _enqueue({'op': 'delete', 'id': id});
      onStatus((s) => s.copyWith(offline: true));
    }
    await _writeCache((await _readCache()).where((r) => r.id != id).toList());
  }

  /// Sends queued changes, oldest first. Stops at the first network error
  /// (still offline). A change the server REJECTS is dropped and reported,
  /// otherwise it would block the queue forever.
  Future<void> flush() => _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<int> pendingCount() async => (await _readOutbox()).length;

  /// Deletes this user's cache and outbox (on sign out).
  Future<void> clearLocal() async {
    for (final k in CacheKeys.allFor(userId)) {
      await store.remove(k);
    }
    onStatus((_) => const SyncStatus());
  }

  // ---------- internals ----------

  Future<void> _flush() async {
    var outbox = await _readOutbox();
    while (outbox.isNotEmpty) {
      final op = outbox.first;
      try {
        if (op['op'] == 'save') {
          await remote.save(ReceiptMapper.fromRow(op['receipt'] as Map<String, dynamic>));
        } else {
          await remote.delete(op['id'] as String);
        }
      } catch (e) {
        if (isNetworkError(e)) {
          onStatus((s) => s.copyWith(offline: true, pending: outbox.length));
          return;
        }
        onStatus((s) => s.copyWith(lastError: () => 'A change could not be synced and was discarded: $e'));
      }
      outbox = outbox.sublist(1);
      await _writeOutbox(outbox);
    }
    onStatus((s) => s.copyWith(pending: 0));
  }

  /// Adds an operation; a newer operation on the same receipt replaces the
  /// older one (only the latest state needs sending).
  Future<void> _enqueue(Map<String, dynamic> op) async {
    final outbox = (await _readOutbox()).where((o) => o['id'] != op['id']).toList()..add(op);
    await _writeOutbox(outbox);
    onStatus((s) => s.copyWith(pending: outbox.length));
  }

  static List<Receipt> _applyOutbox(List<Receipt> list, List<Map<String, dynamic>> outbox) {
    var result = list;
    for (final op in outbox) {
      result = op['op'] == 'save'
          ? _upsert(result, ReceiptMapper.fromRow(op['receipt'] as Map<String, dynamic>))
          : result.where((r) => r.id != op['id']).toList();
    }
    return result;
  }

  /// Insert or replace, keeping newest-first order.
  static List<Receipt> _upsert(List<Receipt> list, Receipt r) =>
      [...list.where((x) => x.id != r.id), r]..sort((a, b) => b.date.compareTo(a.date));

  Future<List<Receipt>> _readCache() async {
    final raw = await store.read(CacheKeys.receipts(userId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(ReceiptMapper.fromRow).toList();
  }

  // The cache uses the same JSON shape as the save payload, which
  // ReceiptMapper can read back (that round trip is unit tested).
  Future<void> _writeCache(List<Receipt> list) => store.write(
      CacheKeys.receipts(userId), jsonEncode([for (final r in list) ReceiptMapper.toPayload(r)]));

  Future<List<Map<String, dynamic>>> _readOutbox() async {
    final raw = await store.read(CacheKeys.outbox(userId));
    return raw == null ? [] : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _writeOutbox(List<Map<String, dynamic>> outbox) =>
      store.write(CacheKeys.outbox(userId), jsonEncode(outbox));
}

/// People: cached for offline READING. Changes need the server (avoids
/// conflicts like a person deleted on one phone but used on another).
class OfflinePeopleRepository implements PeopleRepository {
  final PeopleRepository remote;
  final LocalStore store;
  final String userId;
  final void Function(SyncStatus Function(SyncStatus)) onStatus;

  OfflinePeopleRepository({
    required this.remote,
    required this.store,
    required this.userId,
    required this.onStatus,
  });

  @override
  Future<List<Person>> fetchAll() async {
    try {
      final list = await remote.fetchAll();
      await _write(list);
      onStatus((s) => s.copyWith(offline: false));
      return list;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      onStatus((s) => s.copyWith(offline: true));
      final cached = await _read();
      if (cached == null) rethrow; // never loaded online: nothing to show
      return cached;
    }
  }

  @override
  Future<Person> add(String name) async {
    final p = await remote.add(name);
    await _write([...?await _read(), p]);
    return p;
  }

  @override
  Future<void> rename(String id, String name) async {
    await remote.rename(id, name);
    await _write([for (final p in await _read() ?? <Person>[]) p.id == id ? p.copyWith(name: name) : p]);
  }

  @override
  Future<void> delete(String id) async {
    await remote.delete(id);
    await _write([...?(await _read())?.where((p) => p.id != id)]);
  }

  Future<List<Person>?> _read() async {
    final raw = await store.read(CacheKeys.people(userId));
    if (raw == null) return null;
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(Person.fromMap).toList();
  }

  Future<void> _write(List<Person> list) =>
      store.write(CacheKeys.people(userId), jsonEncode([for (final p in list) p.toMap()]));
}
