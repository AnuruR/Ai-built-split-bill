import '../models/models.dart';
import 'split_calculator.dart';

/// Converts between the app's Receipt model and the database format.
/// Pure functions, so the conversion is unit tested without a database.
abstract final class ReceiptMapper {
  /// The JSON sent to the `save_receipt` database function.
  /// Assignments are computed here with SplitCalculator, so what is saved
  /// is exactly what the summary showed. Throws SplitException if any
  /// item's split is invalid.
  static Map<String, dynamic> toPayload(Receipt r) => {
        ...r.toMap(),
        'items': [
          for (final (pos, item) in r.items.indexed)
            {
              ...item.toMap(),
              'position': pos,
              'assignments': [
                for (final (i, a) in SplitCalculator.splitItem(item).indexed)
                  {
                    'person_id': a.personId,
                    'position': i,
                    'share': item.method == SplitMethod.equal ? null : item.shares[a.personId],
                    'allocated_cents': a.allocatedCents,
                  },
              ],
            },
        ],
      };

  /// Builds a Receipt from a row of
  /// `receipts.select('*, items(*, assignments(*))')`.
  static Receipt fromRow(Map<String, dynamic> row) {
    final itemRows = [...(row['items'] as List? ?? const [])].cast<Map<String, dynamic>>()
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

    final items = [
      for (final ir in itemRows) _itemFromRow(ir),
    ];
    return Receipt.fromMap(row, items: items);
  }

  static ReceiptItem _itemFromRow(Map<String, dynamic> ir) {
    final base = ReceiptItem.fromMap(ir);
    // Person order matters (remainder cents go to the first person).
    final asg = [...(ir['assignments'] as List? ?? const [])].cast<Map<String, dynamic>>()
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return base.copyWith(
      personIds: [for (final a in asg) a['person_id'] as String],
      shares: base.method == SplitMethod.equal
          ? const {}
          : {
              for (final a in asg)
                if (a['share'] != null) a['person_id'] as String: a['share'] as int,
            },
    );
  }
}
