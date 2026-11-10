import 'package:intl/intl.dart';

/// Money is stored everywhere as an `int` number of cents (Rs. 1.00 == 100).
///
/// Why not `double`? Binary floating point cannot represent most decimals
/// exactly: 0.1 + 0.2 == 0.30000000000000004. When you split and re-add
/// amounts those tiny errors pile up and totals stop matching. Integers are
/// exact, so we only convert to a decimal string at the very edge (the UI).
typedef Cents = int;

final NumberFormat _lkr = NumberFormat('#,##0.00', 'en_US');

/// Formats cents as "Rs. 1,234.50".
String formatLkr(Cents cents) {
  final sign = cents < 0 ? '-' : '';
  return '${sign}Rs. ${_lkr.format(cents.abs() / 100)}';
}

/// Parses user/OCR text like "1,234.50", "Rs. 99", "99.5" into cents.
/// Returns null if the text isn't a valid amount. Uses string maths, never
/// doubles, so "0.29" is exactly 29 cents.
Cents? parseCents(String input) {
  final s = input.trim().replaceAll(RegExp(r'rs\.?|lkr', caseSensitive: false), '').replaceAll(',', '').trim();
  final m = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(2)!);
  final frac = (m.group(3) ?? '').padRight(2, '0');
  final value = whole * 100 + int.parse(frac);
  return m.group(1) == '-' ? -value : value;
}
