import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/services/local_store.dart';
import 'package:snapsplit/services/offline_repositories.dart';
import 'package:snapsplit/services/people_repository.dart';
import 'package:snapsplit/services/receipt_repository.dart';
import 'package:snapsplit/services/split_calculator.dart';

/// A fake Supabase: an in-memory repository that can be switched offline
/// (throws SocketException) or made to reject saves (a server error).
class FakeServer implements ReceiptRepository {
  final inner = InMemoryReceiptRepository();
  bool online = true;
  bool rejectSaves = false;
  int saveCalls = 0;

  void _check() {
    if (!online) throw const SocketException('offline');
  }

  @override
  Future<List<Receipt>> fetchAll() async {
    _check();
    return inner.fetchAll();
  }

  @override
  Future<Receipt?> fetchById(String id) async {
    _check();
    return inner.fetchById(id);
  }

  @override
  Future<void> save(Receipt r) async {
    _check();
    saveCalls++;
    if (rejectSaves) throw Exception('new row violates row-level security policy');
    await inner.save(r);
  }

  @override
  Future<void> delete(String id) async {
    _check();
    await inner.delete(id);
  }
}

Receipt receipt(String id, {int cents = 1000, DateTime? date}) => Receipt(
      id: id,
      storeName: 'Store $id',
      date: date ?? DateTime(2026, 11, 1),
      totalCents: cents,
      items: [
        ReceiptItem(id: '$id-i', name: 'RICE', amountCents: cents, personIds: const ['a', 'b']),
      ],
    );

void main() {
  late FakeServer server;
  late MemoryLocalStore store;
  late SyncStatus status;
  late OfflineReceiptRepository repo;

  OfflineReceiptRepository make(String userId) => OfflineReceiptRepository(
        remote: server,
        store: store,
        userId: userId,
        onStatus: (change) => status = change(status),
      );

  setUp(() {
    server = FakeServer();
    store = MemoryLocalStore();
    status = const SyncStatus();
    repo = make('user-1');
  });

  group('reading', () {
    test('online: returns server data and caches it', () async {
      await server.inner.save(receipt('r1'));
      expect((await repo.fetchAll()).single.id, 'r1');
      expect(store.data.containsKey(CacheKeys.receipts('user-1')), isTrue);
      expect(status.offline, isFalse);
    });

    test('offline: returns the cached copy and reports offline', () async {
      await server.inner.save(receipt('r1'));
      await repo.fetchAll(); // cache while online
      server.online = false;
      final list = await repo.fetchAll();
      expect(list.single.id, 'r1');
      expect(status.offline, isTrue);
    });

    test('the cached copy keeps the split exactly', () async {
      await server.inner.save(receipt('r1', cents: 1001));
      await repo.fetchAll();
      server.online = false;
      final r = (await repo.fetchAll()).single;
      expect(SplitCalculator.summarize(r.items).perPerson, {'a': 501, 'b': 500});
    });

    test('offline with no cache yet gives an empty list', () async {
      server.online = false;
      expect(await repo.fetchAll(), isEmpty);
    });

    test('caches are per user', () async {
      await server.inner.save(receipt('r1'));
      await repo.fetchAll();
      server.online = false;
      expect(await make('user-2').fetchAll(), isEmpty);
    });
  });

  group('offline saves (outbox)', () {
    test('online save goes straight to the server', () async {
      await repo.save(receipt('r1'));
      expect(await server.inner.fetchById('r1'), isNotNull);
      expect(await repo.pendingCount(), 0);
    });

    test('offline save is kept on the phone and queued', () async {
      server.online = false;
      await repo.save(receipt('r1'));
      expect(await repo.pendingCount(), 1);
      expect(status.pending, 1);
      expect((await repo.fetchAll()).single.id, 'r1'); // visible offline
      expect(await server.inner.fetchById('r1'), isNull); // not on server yet
    });

    test('when back online, the next load syncs the outbox', () async {
      server.online = false;
      await repo.save(receipt('r1'));
      server.online = true;
      final list = await repo.fetchAll();
      expect(list.single.id, 'r1');
      expect(await server.inner.fetchById('r1'), isNotNull);
      expect(await repo.pendingCount(), 0);
      expect(status.pending, 0);
    });

    test('editing the same receipt twice offline sends only the latest', () async {
      server.online = false;
      await repo.save(receipt('r1', cents: 100));
      await repo.save(receipt('r1', cents: 200));
      expect(await repo.pendingCount(), 1);
      server.online = true;
      await repo.flush();
      expect(server.saveCalls, 1);
      expect((await server.inner.fetchById('r1'))!.totalCents, 200);
    });

    test('offline delete is queued and applied later', () async {
      await repo.save(receipt('r1'));
      server.online = false;
      await repo.delete('r1');
      expect(await repo.fetchAll(), isEmpty);
      server.online = true;
      await repo.flush();
      expect(await server.inner.fetchById('r1'), isNull);
    });

    test('save then delete offline: the receipt never reaches the server', () async {
      server.online = false;
      await repo.save(receipt('r1'));
      await repo.delete('r1');
      expect(await repo.pendingCount(), 1); // just the delete
      server.online = true;
      await repo.flush();
      expect(server.saveCalls, 0);
    });

    test('queued changes are sent in order', () async {
      server.online = false;
      await repo.save(receipt('r1'));
      await repo.save(receipt('r2'));
      server.online = true;
      await repo.flush();
      expect((await server.inner.fetchAll()).map((r) => r.id).toSet(), {'r1', 'r2'});
    });

    test('a change the server rejects is dropped and reported, not retried forever', () async {
      server.online = false;
      await repo.save(receipt('r1'));
      server
        ..online = true
        ..rejectSaves = true;
      await repo.flush();
      expect(await repo.pendingCount(), 0);
      expect(status.lastError, contains('could not be synced'));
    });

    test('a server error while ONLINE is shown, not queued', () async {
      server.rejectSaves = true;
      await expectLater(repo.save(receipt('r1')), throwsException);
      expect(await repo.pendingCount(), 0);
    });

    test('the outbox survives an app restart (new repository, same store)', () async {
      server.online = false;
      await repo.save(receipt('r1'));
      final afterRestart = make('user-1');
      expect(await afterRestart.pendingCount(), 1);
      server.online = true;
      await afterRestart.fetchAll();
      expect(await server.inner.fetchById('r1'), isNotNull);
    });

    test('clearLocal removes the cache and outbox (sign out)', () async {
      server.online = false;
      await repo.save(receipt('r1'));
      await repo.clearLocal();
      expect(await repo.pendingCount(), 0);
      expect(await repo.fetchAll(), isEmpty);
    });
  });

  group('people', () {
    late _FlakyPeople remote;
    late OfflinePeopleRepository people;
    setUp(() {
      remote = _FlakyPeople();
      people = OfflinePeopleRepository(
          remote: remote, store: store, userId: 'user-1', onStatus: (c) => status = c(status));
    });

    test('offline reading uses the cached list', () async {
      await people.fetchAll();
      await people.add('Bimal');
      remote.online = false;
      expect((await people.fetchAll()).map((p) => p.name), ['Me', 'Bimal']);
      expect(status.offline, isTrue);
    });

    test('adding a person offline fails (needs the server)', () async {
      remote.online = false;
      await expectLater(people.add('X'), throwsA(isA<SocketException>()));
    });

    test('offline with nothing cached rethrows so the UI shows an error', () async {
      remote.online = false;
      await expectLater(people.fetchAll(), throwsA(isA<SocketException>()));
    });
  });
}

class _FlakyPeople implements PeopleRepository {
  final inner = InMemoryPeopleRepository();
  bool online = true;
  void _check() {
    if (!online) throw const SocketException('offline');
  }

  @override
  Future<List<Person>> fetchAll() async {
    _check();
    return inner.fetchAll();
  }

  @override
  Future<Person> add(String name) async {
    _check();
    return inner.add(name);
  }

  @override
  Future<void> rename(String id, String name) async {
    _check();
    await inner.rename(id, name);
  }

  @override
  Future<void> delete(String id) async {
    _check();
    await inner.delete(id);
  }
}
