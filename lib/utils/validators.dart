/// Form validators for the auth screens. Each returns an error message,
/// or null when the value is valid (the convention TextFormField expects).
abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(s)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Enter a password';
    if (s.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? requiredText(String? v, String what) =>
      (v == null || v.trim().isEmpty) ? 'Enter $what' : null;

  static String? confirmPassword(String? v, String original) =>
      v != original ? 'Passwords do not match' : null;
}
