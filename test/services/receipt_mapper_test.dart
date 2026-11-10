import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/services/receipt_mapper.dart';
import 'package:snapsplit/services/split_calculator.dart';

void main() {
  final receipt = Receipt(
    id: 'r1',
    storeName: 'KEELLS',
    date: DateTime(2026, 11, 3),
    totalCents: 1100,
    items: const [
      ReceiptItem(id: 'i1', name: 'MILK', amountCents: 100, categoryId: 'dairy', personIds: ['b', 'a', 'c']),
      ReceiptItem(id: 'i2', name: 'RICE', amountCents: 1000, categoryId: 'groceries',
          personIds: ['a', 'b'], method: SplitMethod.percentage, shares: {'a': 2500, 'b': 7500}),
    ],
  );

  group('toPayload', () {
    final p = ReceiptMapper.toPayload(receipt);
    final items = p['items'] as List;

    test('receipt columns', () {
      expect(p['id'], 'r1');
      expect(p['receipt_date'], '2026-11-03');
      expect(p['total_cents'], 1100);
    });

    test('items keep their order', () {
      expect(items.map((i) => (i['name'], i['position'])), [('MILK', 0), ('RICE', 1)]);
    });

    test('assignments contain the calculated amounts, in person order', () {
      final milk = items[0]['assignments'] as List;
      expect(milk.map((a) => (a['person_id'], a['position'], a['allocated_cents'])),
          [('b', 0, 34), ('a', 1, 33), ('c', 2, 33)]);
      expect(milk.every((a) => a['share'] == null), isTrue); // equal: no shares
    });

    test('percentage shares are sent as basis points', () {
      final rice = items[1]['assignments'] as List;
      expect(rice.map((a) => a['share']), [2500, 7500]);
      expect(rice.map((a) => a['allocated_cents']), [250, 750]);
    });

    test('every item\'s assignments sum to the item amount', () {
      for (final i in items) {
        final sum = (i['assignments'] as List).fold<int>(0, (s, a) => s + (a['allocated_cents'] as int));
        expect(sum, i['amount_cents']);
      }
    });

    test('an invalid split is refused before reaching the database', () {
      final bad = receipt.copyWith(items: const [
        ReceiptItem(id: 'x', name: 'X', amountCents: 100, personIds: ['a'],
            method: SplitMethod.exact, shares: {'a': 99}),
      ]);
      expect(() => ReceiptMapper.toPayload(bad), throwsA(isA<SplitException>()));
    });
  });

  group('fromRow', () {
    // Shaped like the PostgREST response, deliberately OUT of order.
    final row = {
      'id': 'r1', 'store_name': 'KEELLS', 'receipt_date': '2026-11-03',
      'total_cents': 1100, 'image_path': null,
      'items': [
        {
          'id': 'i2', 'position': 1, 'name': 'RICE', 'amount_cents': 1000,
          'category_id': 'groceries', 'split_method': 'percentage',
          'assignments': [
            {'person_id': 'b', 'position': 1, 'share': 7500, 'allocated_cents': 750},
            {'person_id': 'a', 'position': 0, 'share': 2500, 'allocated_cents': 250},
          ],
        },
        {
          'id': 'i1', 'position': 0, 'name': 'MILK', 'amount_cents': 100,
          'category_id': 'dairy', 'split_method': 'equal',
          'assignments': [
            {'person_id': 'a', 'position': 1, 'share': null, 'allocated_cents': 33},
            {'person_id': 'c', 'position': 2, 'share': null, 'allocated_cents': 33},
            {'person_id': 'b', 'position': 0, 'share': null, 'allocated_cents': 34},
          ],
        },
      ],
    };
    final r = ReceiptMapper.fromRow(row);

    test('sorts items and people by position', () {
      expect(r.items.map((i) => i.name), ['MILK', 'RICE']);
      expect(r.items[0].personIds, ['b', 'a', 'c']);
      expect(r.items[1].personIds, ['a', 'b']);
    });

    test('restores method and shares', () {
      expect(r.items[1].method, SplitMethod.percentage);
      expect(r.items[1].shares, {'a': 2500, 'b': 7500});
      expect(r.items[0].shares, isEmpty);
    });

    test('recalculating a loaded receipt gives the saved amounts', () {
      final s = SplitCalculator.summarize(r.items);
      expect(s.perPerson, {'b': 784, 'a': 283, 'c': 33});
    });

    test('a receipt with no items', () {
      expect(ReceiptMapper.fromRow({...row, 'items': []}).items, isEmpty);
    });
  });

  test('round trip: payload -> row -> receipt keeps the split', () {
    final p = ReceiptMapper.toPayload(receipt);
    final back = ReceiptMapper.fromRow(p);
    expect(SplitCalculator.summarize(back.items).perPerson,
        SplitCalculator.summarize(receipt.items).perPerson);
  });
}
