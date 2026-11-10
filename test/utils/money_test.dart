import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/utils/money.dart';

void main() {
  group('parseCents', () {
    test('plain and decimal values', () {
      expect(parseCents('99'), 9900);
      expect(parseCents('99.5'), 9950);
      expect(parseCents('0.29'), 29); // would be 28.999... with doubles
    });
    test('commas and Rs. prefix', () {
      expect(parseCents('Rs. 1,234.50'), 123450);
      expect(parseCents('LKR 10'), 1000);
    });
    test('negative', () => expect(parseCents('-12.00'), -1200));
    test('invalid text returns null', () {
      expect(parseCents(''), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents('1.234'), isNull);
    });
  });

  group('formatLkr', () {
    test('formats with thousands separator', () => expect(formatLkr(123450), 'Rs. 1,234.50'));
    test('negative', () => expect(formatLkr(-5), '-Rs. 0.05'));
  });
}
