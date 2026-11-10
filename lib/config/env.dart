/// Build-time configuration, passed with:
///   flutter run --dart-define-from-file=env/dev.json
///
/// `String.fromEnvironment` is resolved at COMPILE time, so the values
/// never have to be written in a .dart file that is committed to git.
/// (env/*.json is in .gitignore.)
///
/// Note: the publishable/anon key is not really a secret – it ships inside
/// every APK. What protects the data is Row Level Security in the database.
/// Keeping it out of git is still good practice, and makes it easy for each
/// group member to point at their own project.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
