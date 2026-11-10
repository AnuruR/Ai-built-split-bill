import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/services/receipt_filter.dart';

Receipt r(String id, String store, DateTime date, List<(String, int, String)> items) => Receipt(
      id: id,
      storeName: store,
      date: date,
      totalCents: items.fold(0, (s, i) => s + i.$2),
      items: [
        for (final (n, c, cat) in items)
          ReceiptItem(id: '$id-$n', name: n, amountCents: c, categoryId: cat),
      ],
    );

void main() {
  final keells = r('1', 'KEELLS SUPER', DateTime(2026, 11, 3), [('MILK', 450, 'dairy'), ('SOAP', 100, 'household')]);
  final cargills = r('2', 'Cargills Food City', DateTime(2026, 10, 31), [('BREAD', 180, 'bakery')]);
  final pureFood = r('3', 'Pure Food', DateTime(2026, 11, 10), [('Fried Rice', 350, 'dining'), ('Milk Tea', 100, 'beverages')]);
  final all = [pureFood, keells, cargills];

  List<String> ids(List<Receipt> l) => l.map((x) => x.id).toList();

  group('search', () {
    test('empty query returns everything in order', () => expect(ids(ReceiptFilter.apply(all)), ['3', '1', '2']));
    test('matches store name, case-insensitive', () => expect(ids(ReceiptFilter.apply(all, query: 'keells')), ['1']));
    test('matches item names', () => expect(ids(ReceiptFilter.apply(all, query: 'milk')), ['3', '1']));
    test('surrounding spaces ignored', () => expect(ids(ReceiptFilter.apply(all, query: '  bread ')), ['2']));
    test('no match', () => expect(ReceiptFilter.apply(all, query: 'arpico'), isEmpty));
  });

  group('filters', () {
    test('category', () => expect(ids(ReceiptFilter.apply(all, categoryId: 'dairy')), ['1']));

    test('date range is inclusive on both ends', () {
      expect(ids(ReceiptFilter.apply(all, from: DateTime(2026, 10, 31), to: DateTime(2026, 11, 3))), ['1', '2']);
    });

    test('time of day on the range does not exclude a receipt', () {
      expect(ids(ReceiptFilter.apply(all, from: DateTime(2026, 11, 3, 23, 59), to: DateTime(2026, 11, 3))), ['1']);
    });

    test('filters combine (AND)', () {
      expect(ids(ReceiptFilter.apply(all, query: 'milk', categoryId: 'beverages')), ['3']);
      expect(ReceiptFilter.apply(all, query: 'bread', from: DateTime(2026, 11, 1)), isEmpty);
    });
  });

  group('stats', () {
    test('inMonth', () => expect(ids(ReceiptFilter.inMonth(all, DateTime(2026, 11, 20))), ['3', '1']));

    test('categoryTotals sums across receipts, largest first', () {
      final t = ReceiptFilter.categoryTotals(ReceiptFilter.inMonth(all, DateTime(2026, 11, 1)));
      expect(t.map((e) => (e.key, e.value)), [('dairy', 450), ('dining', 350), ('beverages', 100), ('household', 100)]);
    });

    test('no receipts gives no totals', () => expect(ReceiptFilter.categoryTotals([]), isEmpty));
  });
}
