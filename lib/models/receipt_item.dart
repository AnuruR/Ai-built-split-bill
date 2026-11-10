import '../utils/money.dart';
import 'split_method.dart';

/// One line on a receipt.
///
/// Besides name/amount/category it remembers *how* it is split:
/// [personIds] (who shares it), [method], and [shares] – the raw user input
/// for exact (cents per person) or percentage (basis points, 100% = 10000)
/// splits. The final per-person amounts are computed from these.
class ReceiptItem {
  final String id;
  final String name;
  final Cents amountCents;
  final String categoryId;
  final List<String> personIds;
  final SplitMethod method;
  final Map<String, int> shares;

  const ReceiptItem({
    required this.id,
    required this.name,
    required this.amountCents,
    this.categoryId = 'other',
    this.personIds = const [],
    this.method = SplitMethod.equal,
    this.shares = const {},
  });

  ReceiptItem copyWith({
    String? name,
    Cents? amountCents,
    String? categoryId,
    List<String>? personIds,
    SplitMethod? method,
    Map<String, int>? shares,
  }) =>
      ReceiptItem(
        id: id,
        name: name ?? this.name,
        amountCents: amountCents ?? this.amountCents,
        categoryId: categoryId ?? this.categoryId,
        personIds: personIds ?? this.personIds,
        method: method ?? this.method,
        shares: shares ?? this.shares,
      );

  factory ReceiptItem.fromMap(Map<String, dynamic> map) => ReceiptItem(
        id: map['id'] as String,
        name: map['name'] as String,
        amountCents: map['amount_cents'] as int,
        categoryId: (map['category_id'] as String?) ?? 'other',
        method: SplitMethod.fromName(map['split_method'] as String?),
      );

  /// Item columns only; assignments are stored in their own table.
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'amount_cents': amountCents,
        'category_id': categoryId,
        'split_method': method.name,
      };
}
