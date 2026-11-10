import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/services/split_calculator.dart';

/// Helper: adds up a split result.
int sumOf(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

/// Matcher for "throws a SplitException".
final throwsSplit = throwsA(isA<SplitException>());

void main() {
  const a = 'amal', b = 'bimal', c = 'chathu';

  group('equal split', () {
    test('single person gets the full amount', () {
      expect(SplitCalculator.equal(12550, [a]), {a: 12550});
    });

    test('divides evenly when possible', () {
      expect(SplitCalculator.equal(30000, [a, b, c]), {a: 10000, b: 10000, c: 10000});
    });

    test('leftover cent goes to the first person (Rs.1.00 / 3)', () {
      expect(SplitCalculator.equal(100, [a, b, c]), {a: 34, b: 33, c: 33});
    });

    test('two leftover cents both go to the first person', () {
      // 200 / 3 = 66 r 2
      expect(SplitCalculator.equal(200, [a, b, c]), {a: 68, b: 66, c: 66});
    });

    test('order of people decides who gets the remainder', () {
      expect(SplitCalculator.equal(100, [c, a, b]), {c: 34, a: 33, b: 33});
    });

    test('amount smaller than number of people', () {
      expect(SplitCalculator.equal(2, [a, b, c]), {a: 2, b: 0, c: 0});
    });

    test('zero amount', () {
      expect(SplitCalculator.equal(0, [a, b]), {a: 0, b: 0});
    });

    test('negative amount (discount line) still sums exactly', () {
      final r = SplitCalculator.equal(-100, [a, b, c]);
      expect(r, {a: -34, b: -33, c: -33});
      expect(sumOf(r), -100);
    });

    test('is deterministic', () {
      expect(SplitCalculator.equal(1001, [a, b, c]),
          SplitCalculator.equal(1001, [a, b, c]));
    });

    test('empty people list throws', () {
      expect(() => SplitCalculator.equal(100, []), throwsSplit);
    });

    test('duplicate person throws', () {
      expect(() => SplitCalculator.equal(100, [a, a]), throwsSplit);
    });

    // Property-style test: the invariant must hold for many inputs.
    test('sum always equals the amount (1..20 people, many amounts)', () {
      for (var n = 1; n <= 20; n++) {
        final people = List.generate(n, (i) => 'p$i');
        for (final amount in [0, 1, 7, 99, 100, 101, 12345, 999999, -1, -777]) {
          final r = SplitCalculator.equal(amount, people);
          expect(sumOf(r), amount, reason: 'amount=$amount n=$n');
          // Nobody differs from the base share by more than the remainder.
          final shares = r.values.toList();
          expect(shares.skip(1).toSet().length <= 1, isTrue);
        }
      }
    });
  });

  group('exact split', () {
    test('accepts shares that add up to the amount', () {
      expect(SplitCalculator.exact(1000, [a, b], {a: 700, b: 300}), {a: 700, b: 300});
    });

    test('allows a zero share', () {
      expect(SplitCalculator.exact(1000, [a, b], {a: 1000, b: 0}), {a: 1000, b: 0});
    });

    test('result follows personIds order', () {
      final r = SplitCalculator.exact(1000, [b, a], {a: 700, b: 300});
      expect(r.keys.toList(), [b, a]);
    });

    test('shares adding up to LESS than the amount throw', () {
      expect(() => SplitCalculator.exact(1000, [a, b], {a: 500, b: 499}), throwsSplit);
    });

    test('shares adding up to MORE than the amount throw', () {
      expect(() => SplitCalculator.exact(1000, [a, b], {a: 500, b: 501}), throwsSplit);
    });

    test('negative share on a positive item throws', () {
      expect(() => SplitCalculator.exact(1000, [a, b], {a: 1100, b: -100}), throwsSplit);
    });

    test('negative item with negative shares is valid', () {
      expect(SplitCalculator.exact(-500, [a, b], {a: -200, b: -300}), {a: -200, b: -300});
    });

    test('missing share for an assigned person throws', () {
      expect(() => SplitCalculator.exact(1000, [a, b], {a: 1000}), throwsSplit);
    });

    test('share for someone not assigned throws', () {
      expect(() => SplitCalculator.exact(1000, [a], {a: 1000, b: 0}), throwsSplit);
    });

    test('empty people list throws', () {
      expect(() => SplitCalculator.exact(1000, [], {}), throwsSplit);
    });
  });

  group('percentage split', () {
    test('50/50', () {
      expect(SplitCalculator.percentage(1000, [a, b], {a: 5000, b: 5000}), {a: 500, b: 500});
    });

    test('100% to one person', () {
      expect(SplitCalculator.percentage(1234, [a], {a: 10000}), {a: 1234});
    });

    test('0% share is allowed', () {
      expect(SplitCalculator.percentage(1000, [a, b], {a: 10000, b: 0}), {a: 1000, b: 0});
    });

    test('33.33/33.33/33.34 on Rs.1.00: remainder goes to first person', () {
      // 100*3333/10000 = 33.33 -> 33 ; 100*3334/10000 = 33.34 -> 33
      // allocated 99, so the first person gets +1.
      final r = SplitCalculator.percentage(100, [a, b, c], {a: 3333, b: 3333, c: 3334});
      expect(r, {a: 34, b: 33, c: 33});
    });

    test('uneven 70/30 with rounding', () {
      // 999 * 0.7 = 699.3 -> 699 ; 999 * 0.3 = 299.7 -> 299 ; leftover 1 -> a
      expect(SplitCalculator.percentage(999, [a, b], {a: 7000, b: 3000}), {a: 700, b: 299});
    });

    test('negative amount sums exactly', () {
      final r = SplitCalculator.percentage(-999, [a, b], {a: 7000, b: 3000});
      expect(sumOf(r), -999);
    });

    test('percentages under 100% throw', () {
      expect(() => SplitCalculator.percentage(1000, [a, b], {a: 5000, b: 4999}), throwsSplit);
    });

    test('percentages over 100% throw', () {
      expect(() => SplitCalculator.percentage(1000, [a, b], {a: 6000, b: 5000}), throwsSplit);
    });

    test('negative percentage throws even if total is 100%', () {
      expect(() => SplitCalculator.percentage(1000, [a, b], {a: 11000, b: -1000}), throwsSplit);
    });

    test('missing percentage throws', () {
      expect(() => SplitCalculator.percentage(1000, [a, b], {a: 10000}), throwsSplit);
    });

    test('sum always equals the amount for many inputs', () {
      final splits = [
        {a: 3333, b: 3333, c: 3334},
        {a: 1, b: 9998, c: 1},
        {a: 2500, b: 2500, c: 5000},
        {a: 0, b: 0, c: 10000},
      ];
      for (final p in splits) {
        for (final amount in [0, 1, 2, 99, 101, 54321, -77]) {
          expect(sumOf(SplitCalculator.percentage(amount, [a, b, c], p)), amount,
              reason: 'amount=$amount p=$p');
        }
      }
    });
  });

  group('splitItem', () {
    test('uses the item method and produces Assignments', () {
      const item = ReceiptItem(
          id: 'i1', name: 'Milk', amountCents: 100, personIds: [a, b, c]);
      final r = SplitCalculator.splitItem(item);
      expect(r.map((x) => x.itemId).toSet(), {'i1'});
      expect(r.map((x) => x.allocatedCents).toList(), [34, 33, 33]);
    });

    test('percentage item uses its shares', () {
      const item = ReceiptItem(
        id: 'i2', name: 'Rice', amountCents: 1000, personIds: [a, b],
        method: SplitMethod.percentage, shares: {a: 2500, b: 7500},
      );
      expect(SplitCalculator.splitItem(item).map((x) => x.allocatedCents), [250, 750]);
    });

    test('exact item with bad shares throws', () {
      const item = ReceiptItem(
        id: 'i3', name: 'Tea', amountCents: 1000, personIds: [a, b],
        method: SplitMethod.exact, shares: {a: 100, b: 100},
      );
      expect(() => SplitCalculator.splitItem(item), throwsSplit);
    });
  });

  group('summarize', () {
    const items = [
      ReceiptItem(id: '1', name: 'Bread', amountCents: 25000, categoryId: 'bakery', personIds: [a]),
      ReceiptItem(id: '2', name: 'Milk', amountCents: 100, categoryId: 'dairy', personIds: [a, b, c]),
      ReceiptItem(id: '3', name: 'Cheese', amountCents: 90000, categoryId: 'dairy',
          personIds: [b, c], method: SplitMethod.exact, shares: {b: 60000, c: 30000}),
      ReceiptItem(id: '4', name: 'Soap', amountCents: 15000, categoryId: 'household'),
    ];

    final s = SplitCalculator.summarize(items);

    test('single-person item gives the full amount to that person', () {
      // a: 25000 bread + 34 milk
      expect(s.perPerson[a], 25034);
    });

    test('per-person totals', () {
      expect(s.perPerson, {a: 25034, b: 60033, c: 30033});
    });

    test('per-category totals', () {
      expect(s.perCategory, {'bakery': 25000, 'dairy': 90100, 'household': 15000});
    });

    test('unassigned items are reported, not lost', () {
      expect(s.unassignedCents, 15000);
    });

    test('person totals + unassigned == items total', () {
      expect(sumOf(s.perPerson) + s.unassignedCents, s.itemsTotalCents);
      expect(s.itemsTotalCents, 130100);
    });

    test('empty receipt gives zero totals', () {
      final e = SplitCalculator.summarize([]);
      expect(e.perPerson, isEmpty);
      expect(e.itemsTotalCents, 0);
    });
  });

  group('breakdown', () {
    const items = [
      ReceiptItem(id: '1', name: 'Bread', amountCents: 300, personIds: [a]),
      ReceiptItem(id: '2', name: 'Milk', amountCents: 100, personIds: [a, b]),
      ReceiptItem(id: '3', name: 'Soap', amountCents: 50),
    ];
    final bd = SplitCalculator.breakdown(items);

    test('lists each item a person pays for', () {
      expect(bd[a]!.map((e) => (e.$1.name, e.$2)), [('Bread', 300), ('Milk', 50)]);
      expect(bd[b]!.map((e) => (e.$1.name, e.$2)), [('Milk', 50)]);
    });

    test('breakdown totals equal summarize totals', () {
      final s = SplitCalculator.summarize(items);
      for (final id in [a, b]) {
        expect(bd[id]!.fold<int>(0, (t, e) => t + e.$2), s.perPerson[id]);
      }
    });

    test('unassigned items are not in any breakdown', () {
      expect(bd.values.expand((l) => l).any((e) => e.$1.id == '3'), isFalse);
    });
  });
}
