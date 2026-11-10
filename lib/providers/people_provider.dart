import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/person.dart';
import '../services/people_repository.dart';
import '../services/supabase_repositories.dart';
import '../services/offline_repositories.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// Supabase-backed. Watching currentUserIdProvider rebuilds it (and so
/// reloads people) whenever a different user signs in.
/// Tests override this with InMemoryPeopleRepository.
final peopleRepositoryProvider = Provider<PeopleRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider).value ?? 'signed-out';
  // Cached copy for offline reading; changes still need the server.
  return OfflinePeopleRepository(
    remote: SupabasePeopleRepository(ref.watch(supabaseClientProvider)),
    store: ref.watch(localStoreProvider),
    userId: userId,
    onStatus: (change) => ref.read(syncStatusProvider.notifier).update(change),
  );
});

/// The signed-in user's people (FR-08).
///
/// An AsyncNotifier's state is an AsyncValue: loading, data, or error.
/// Screens use `.when(...)` to show a spinner, the list, or an error message.
class PeopleNotifier extends AsyncNotifier<List<Person>> {
  PeopleRepository get _repo => ref.read(peopleRepositoryProvider);

  // ref.watch: if the repository is replaced (user changed), reload.
  @override
  Future<List<Person>> build() => ref.watch(peopleRepositoryProvider).fetchAll();

  /// Returns an error message, or null if the name is OK.
  String? validateName(String name, {String? exceptId}) {
    final n = name.trim();
    if (n.isEmpty) return 'Enter a name';
    if (n.length > 40) return 'Name is too long';
    final taken = (state.value ?? []).any(
        (p) => p.id != exceptId && p.name.toLowerCase() == n.toLowerCase());
    return taken ? 'Someone with that name already exists' : null;
  }

  Future<Person> add(String name) async {
    final person = await _repo.add(name.trim());
    state = AsyncData([...?state.value, person]);
    return person;
  }

  Future<void> rename(String id, String name) async {
    await _repo.rename(id, name.trim());
    state = AsyncData([
      for (final p in state.value ?? <Person>[]) p.id == id ? p.copyWith(name: name.trim()) : p,
    ]);
  }

  Future<void> remove(String id) async {
    await _repo.delete(id);
    state = AsyncData((state.value ?? []).where((p) => p.id != id).toList());
  }
}

final peopleProvider = AsyncNotifierProvider<PeopleNotifier, List<Person>>(PeopleNotifier.new);
