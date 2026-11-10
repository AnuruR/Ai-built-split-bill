import '../models/receipt.dart';
import '../utils/money.dart';

/// Pure search/filter/statistics helpers for saved receipts (FR-12, S01).
abstract final class ReceiptFilter {
  /// Keeps receipts that match ALL given filters:
  /// - [query]: case-insensitive match on the store name or any item name
  /// - [categoryId]: has at least one item in that category
  /// - [from]/[to]: receipt date within the range (inclusive, by day)
  static List<Receipt> apply(
    List<Receipt> receipts, {
    String query = '',
    String? categoryId,
    DateTime? from,
    DateTime? to,
  }) {
    final q = query.trim().toLowerCase();
    final fromDay = from == null ? null : DateTime(from.year, from.month, from.day);
    final toDay = to == null ? null : DateTime(to.year, to.month, to.day);
    return receipts.where((r) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      if (fromDay != null && day.isBefore(fromDay)) return false;
      if (toDay != null && day.isAfter(toDay)) return false;
      if (categoryId != null && !r.items.any((i) => i.categoryId == categoryId)) return false;
      if (q.isEmpty) return true;
      return r.storeName.toLowerCase().contains(q) ||
          r.items.any((i) => i.name.toLowerCase().contains(q));
    }).toList();
  }

  /// Receipts dated in the same calendar month as [now].
  static List<Receipt> inMonth(List<Receipt> receipts, DateTime now) => receipts
      .where((r) => r.date.year == now.year && r.date.month == now.month)
      .toList();

  /// Spending per category across receipts, largest first. Equal totals
  /// are ordered by category id so the order never changes between runs
  /// (Dart's sort is not guaranteed to be stable).
  static List<MapEntry<String, Cents>> categoryTotals(List<Receipt> receipts) {
    final totals = <String, Cents>{};
    for (final r in receipts) {
      for (final i in r.items) {
        totals.update(i.categoryId, (v) => v + i.amountCents, ifAbsent: () => i.amountCents);
      }
    }
    return totals.entries.toList()
      ..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);
        return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
      });
  }
}
