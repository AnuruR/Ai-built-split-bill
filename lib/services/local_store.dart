import 'package:shared_preferences/shared_preferences.dart';

/// Tiny key/value store for the offline cache and outbox.
/// An interface so tests can use [MemoryLocalStore] instead of the device.
///
/// SharedPreferences is enough here: a student's receipts are a few hundred
/// KB of JSON at most. A bigger app would use SQLite (e.g. drift).
abstract interface class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPrefsLocalStore implements LocalStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);
  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

class MemoryLocalStore implements LocalStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// Cache keys are per user, so two accounts on one phone never mix data.
abstract final class CacheKeys {
  static String receipts(String userId) => 'cache.$userId.receipts';
  static String people(String userId) => 'cache.$userId.people';
  static String outbox(String userId) => 'outbox.$userId';

  static List<String> allFor(String userId) =>
      [receipts(userId), people(userId), outbox(userId)];
}
