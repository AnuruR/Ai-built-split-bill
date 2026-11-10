import 'package:uuid/uuid.dart';

import '../models/person.dart';

/// Where people are stored. Screens/providers depend on this INTERFACE,
/// not on a concrete database. Phase 7 adds a Supabase implementation and
/// swaps it in with one line in the provider – nothing else changes.
/// (This is the "repository pattern" / dependency inversion.)
abstract interface class PeopleRepository {
  Future<List<Person>> fetchAll();
  Future<Person> add(String name);
  Future<void> rename(String id, String name);
  Future<void> delete(String id);
}

/// Keeps people in memory (lost when the app closes). Used until Supabase
/// is connected, and in tests.
class InMemoryPeopleRepository implements PeopleRepository {
  final List<Person> _people;
  InMemoryPeopleRepository([List<Person>? initial])
      : _people = initial ?? [const Person(id: 'me', name: 'Me')];

  @override
  Future<List<Person>> fetchAll() async => List.unmodifiable(_people);

  @override
  Future<Person> add(String name) async {
    final p = Person(id: const Uuid().v4(), name: name);
    _people.add(p);
    return p;
  }

  @override
  Future<void> rename(String id, String name) async {
    final i = _people.indexWhere((p) => p.id == id);
    if (i >= 0) _people[i] = _people[i].copyWith(name: name);
  }

  @override
  Future<void> delete(String id) async => _people.removeWhere((p) => p.id == id);
}
