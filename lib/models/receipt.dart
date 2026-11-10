import '../utils/money.dart';
import 'receipt_item.dart';

/// A scanned receipt. [totalCents] is the total *printed on the receipt*
/// (from OCR or typed by the user); the sum of [items] should match it.
class Receipt {
  final String id;
  final String storeName;
  final DateTime date;
  final Cents totalCents;
  /// Where the receipt photo lives. For now a local file path on this
  /// device. Kept as an opaque string on purpose: later it can hold a
  /// Supabase Storage object key instead, without changing the model or
  /// the database column (only the code that loads the image).
  final String? imagePath;
  final List<ReceiptItem> items;

  const Receipt({
    required this.id,
    required this.storeName,
    required this.date,
    required this.totalCents,
    this.imagePath,
    this.items = const [],
  });

  /// Sum of the item amounts (may differ from [totalCents] if OCR missed
  /// something – the review screen warns about this).
  Cents get itemsSumCents => items.fold(0, (sum, i) => sum + i.amountCents);

  bool get isReconciled => itemsSumCents == totalCents;

  Receipt copyWith({
    String? storeName,
    DateTime? date,
    Cents? totalCents,
    String? imagePath,
    List<ReceiptItem>? items,
  }) =>
      Receipt(
        id: id,
        storeName: storeName ?? this.storeName,
        date: date ?? this.date,
        totalCents: totalCents ?? this.totalCents,
        imagePath: imagePath ?? this.imagePath,
        items: items ?? this.items,
      );

  factory Receipt.fromMap(Map<String, dynamic> map, {List<ReceiptItem> items = const []}) =>
      Receipt(
        id: map['id'] as String,
        storeName: map['store_name'] as String,
        date: DateTime.parse(map['receipt_date'] as String),
        totalCents: map['total_cents'] as int,
        imagePath: map['image_path'] as String?,
        items: items,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_name': storeName,
        'receipt_date': date.toIso8601String().substring(0, 10),
        'total_cents': totalCents,
        'image_path': imagePath,
      };
}
