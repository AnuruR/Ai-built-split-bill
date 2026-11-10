import '../utils/money.dart';

/// Links one item to one person with the amount that person pays for it.
/// The amounts of all assignments of an item always sum to the item amount
/// (enforced by SplitCalculator in Phase 2).
class Assignment {
  final String itemId;
  final String personId;
  final Cents allocatedCents;

  const Assignment({
    required this.itemId,
    required this.personId,
    required this.allocatedCents,
  });

  factory Assignment.fromMap(Map<String, dynamic> map) => Assignment(
        itemId: map['item_id'] as String,
        personId: map['person_id'] as String,
        allocatedCents: map['allocated_cents'] as int,
      );

  Map<String, dynamic> toMap() => {
        'item_id': itemId,
        'person_id': personId,
        'allocated_cents': allocatedCents,
      };
}
