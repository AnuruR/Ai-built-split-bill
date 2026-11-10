import '../models/models.dart';
import '../utils/money.dart';

/// Thrown when split input can't produce a valid split
/// (e.g. percentages that don't add up to 100%).
class SplitException implements Exception {
  final String message;
  const SplitException(this.message);
  @override
  String toString() => 'SplitException: $message';
}

/// Totals for a whole receipt (FR-11).
class SplitSummary {
  /// What each person owes, keyed by person id.
  final Map<String, Cents> perPerson;

  /// Spending per category, keyed by category id.
  final Map<String, Cents> perCategory;

  /// Sum of items nobody has been assigned to yet.
  final Cents unassignedCents;

  /// Sum of all item amounts.
  final Cents itemsTotalCents;

  const SplitSummary({
    required this.perPerson,
    required this.perCategory,
    required this.unassignedCents,
    required this.itemsTotalCents,
  });
}

/// Pure Dart split logic. It has no Flutter, database or UI code, so it can
/// be unit tested in isolation. Every method is deterministic: the same input
/// always gives the same output.
///
/// Invariant (always holds when a method returns normally):
///   sum of returned amounts == item amount, to the cent.
///
/// Rounding rule: amounts are rounded towards zero, and the cents left over
/// all go to the FIRST person in the list. Example: Rs. 1.00 split equally
/// between 3 people gives 34 + 33 + 33 cents.
///
/// Percentages are given in basis points (1% = 100, 100% = 10000), so the
/// UI can accept values like 33.33% without using doubles.
class SplitCalculator {
  const SplitCalculator._(); // Static only; never instantiated.

  static const int fullPercentBp = 10000;

  /// Splits [amount] equally between [personIds].
  static Map<String, Cents> equal(Cents amount, List<String> personIds) {
    _checkPeople(personIds);
    final n = personIds.length;
    // `~/` is integer division and rounds towards zero, which also works
    // for negative amounts such as discount lines.
    final base = amount ~/ n;
    final remainder = amount - base * n;
    return {
      for (var i = 0; i < n; i++) personIds[i]: base + (i == 0 ? remainder : 0),
    };
  }

  /// Uses the exact amounts the user typed. [shares] must have an entry for
  /// every person and add up to [amount].
  static Map<String, Cents> exact(
    Cents amount,
    List<String> personIds,
    Map<String, Cents> shares,
  ) {
    _checkPeople(personIds);
    _checkSharesMatchPeople(personIds, shares);
    for (final id in personIds) {
      final s = shares[id]!;
      // A share must have the same sign as the item (e.g. no -50 on a +100 item).
      if ((amount >= 0 && s < 0) || (amount < 0 && s > 0)) {
        throw SplitException('Share for $id has the wrong sign.');
      }
    }
    final sum = shares.values.fold<int>(0, (a, b) => a + b);
    if (sum != amount) {
      throw SplitException(
        'Exact shares add up to ${formatLkr(sum)} but the item is ${formatLkr(amount)}.',
      );
    }
    // Return in personIds order for a predictable result.
    return {for (final id in personIds) id: shares[id]!};
  }

  /// Splits [amount] by percentage. [percentBp] holds basis points per
  /// person and must add up to exactly 10000 (100%).
  static Map<String, Cents> percentage(
    Cents amount,
    List<String> personIds,
    Map<String, int> percentBp,
  ) {
    _checkPeople(personIds);
    _checkSharesMatchPeople(personIds, percentBp);
    if (percentBp.values.any((p) => p < 0)) {
      throw const SplitException('Percentages cannot be negative.');
    }
    final total = percentBp.values.fold<int>(0, (a, b) => a + b);
    if (total != fullPercentBp) {
      throw SplitException('Percentages add up to ${total / 100}%, not 100%.');
    }
    final result = {
      for (final id in personIds) id: amount * percentBp[id]! ~/ fullPercentBp,
    };
    final allocated = result.values.fold<int>(0, (a, b) => a + b);
    result[personIds.first] = result[personIds.first]! + (amount - allocated);
    return result;
  }

  /// Splits one item using its own method, people and shares.
  static List<Assignment> splitItem(ReceiptItem item) {
    final amounts = switch (item.method) {
      SplitMethod.equal => equal(item.amountCents, item.personIds),
      SplitMethod.exact => exact(item.amountCents, item.personIds, item.shares),
      SplitMethod.percentage =>
        percentage(item.amountCents, item.personIds, item.shares),
    };
    return [
      for (final e in amounts.entries)
        Assignment(itemId: item.id, personId: e.key, allocatedCents: e.value),
    ];
  }

  /// Totals for a list of items. Items with no people are counted as
  /// unassigned instead of throwing, so the summary can show what's missing.
  /// Throws [SplitException] if an assigned item has invalid shares.
  static SplitSummary summarize(List<ReceiptItem> items) {
    final perPerson = <String, Cents>{};
    final perCategory = <String, Cents>{};
    var unassigned = 0;
    var total = 0;
    for (final item in items) {
      total += item.amountCents;
      perCategory.update(item.categoryId, (v) => v + item.amountCents,
          ifAbsent: () => item.amountCents);
      if (item.personIds.isEmpty) {
        unassigned += item.amountCents;
        continue;
      }
      for (final a in splitItem(item)) {
        perPerson.update(a.personId, (v) => v + a.allocatedCents,
            ifAbsent: () => a.allocatedCents);
      }
    }
    return SplitSummary(
      perPerson: perPerson,
      perCategory: perCategory,
      unassignedCents: unassigned,
      itemsTotalCents: total,
    );
  }

  /// For each person, the items they pay for and how much of each.
  /// Used by the summary screen's per-person breakdown.
  static Map<String, List<(ReceiptItem, Cents)>> breakdown(List<ReceiptItem> items) {
    final result = <String, List<(ReceiptItem, Cents)>>{};
    for (final item in items) {
      if (item.personIds.isEmpty) continue;
      for (final a in splitItem(item)) {
        (result[a.personId] ??= []).add((item, a.allocatedCents));
      }
    }
    return result;
  }

  // ---- validation helpers ----

  static void _checkPeople(List<String> personIds) {
    if (personIds.isEmpty) {
      throw const SplitException('Assign at least one person.');
    }
    if (personIds.toSet().length != personIds.length) {
      throw const SplitException('The same person is assigned twice.');
    }
  }

  static void _checkSharesMatchPeople(List<String> personIds, Map<String, int> shares) {
    final missing = personIds.where((id) => !shares.containsKey(id));
    if (missing.isNotEmpty) {
      throw SplitException('No share given for: ${missing.join(', ')}.');
    }
    final extra = shares.keys.where((id) => !personIds.contains(id));
    if (extra.isNotEmpty) {
      throw SplitException('Share given for someone not assigned: ${extra.join(', ')}.');
    }
  }
}
