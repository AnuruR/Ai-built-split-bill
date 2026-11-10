import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/services/ocr_service.dart';
import 'package:snapsplit/services/receipt_parser.dart';

/// Sample OCR outputs modelled on Sri Lankan supermarket receipts.
/// When you scan a real receipt, copy the "OCR rows" from the debug console
/// into a new test like these.
const keells = '''
KEELLS SUPER
No. 123, Galle Road, Matara
TEL 041 2234567
DATE: 12/10/2026   TIME: 18:42
INVOICE NO: 004512
ITEM   QTY   PRICE   AMOUNT
ANCHOR MILK POWDER 400G
1.000  1,150.00  1,150.00
SANDWICH BREAD  1  180.00  180.00
BANANA AMBUL
0.750  320.00  240.00
SUB TOTAL   1,570.00
TOTAL   Rs. 1,570.00
CASH   2,000.00
BALANCE   430.00
NO OF ITEMS 3
''';

const cargills = '''
CARGILLS FOOD CITY
Kandy Road, Peradeniya
05-11-26 10:15
001 KOTMALE FRESH MILK 1L   450.00
002 MUNCHEE CRACKER   2 x 225.00
003 SUNLIGHT SOAP   3 @ 95.50   286.50
DISCOUNT   -50.00
NET TOTAL   Rs. 1,136.50
VISA   1,136.50
''';

ParsedReceipt p(String text) => ReceiptParser.parse(text);

void main() {
  group('full receipts', () {
    test('Keells: two-row items, quantity columns, total', () {
      final r = p(keells);
      expect(r.items, const [
        ParsedItem('ANCHOR MILK POWDER 400G', 115000),
        ParsedItem('SANDWICH BREAD', 18000),
        ParsedItem('BANANA AMBUL', 24000),
      ]);
      expect(r.totalCents, 157000);
      expect(r.storeName, 'KEELLS SUPER');
      expect(r.date, DateTime(2026, 10, 12));
    });

    test('Keells: item sum reconciles with the total', () {
      final r = p(keells);
      expect(r.items.fold<int>(0, (s, i) => s + i.amountCents), r.totalCents);
    });

    test('Cargills: item codes, "x" and "@" quantities, discount, NET TOTAL', () {
      final r = p(cargills);
      expect(r.items, const [
        ParsedItem('KOTMALE FRESH MILK 1L', 45000),
        ParsedItem('MUNCHEE CRACKER', 45000),
        ParsedItem('SUNLIGHT SOAP', 28650),
        ParsedItem('DISCOUNT', -5000),
      ]);
      expect(r.totalCents, 113650);
      expect(r.storeName, 'CARGILLS FOOD CITY');
      expect(r.date, DateTime(2026, 11, 5));
    });
  });

  group('real receipts', () {
    // From a real restaurant bill scanned on 2026-11-11 (as shown on S03).
    test('Pure Food: two-row item, junk symbols, zero discount skipped', () {
      final r = p('''
Pure Food
2026-11-03
Vegetable Fried Rice H *x
Rs. 350.00
Discourt
Rs. 0.00
''');
      expect(r.items, const [ParsedItem('Vegetable Fried Rice H', 35000)]);
      expect(r.date, DateTime(2026, 11, 3));
      expect(r.storeName, 'Pure Food');
    });
  });

  group('prices', () {
    test('zero-amount lines are skipped', () {
      expect(p('SERVICE CHARGE 0.00\nTEA 10.00').items, const [ParsedItem('TEA', 1000)]);
    });


    test('Rs. prefix and thousands commas', () {
      expect(p('RICE 5KG  Rs. 1,250.00').items, const [ParsedItem('RICE 5KG', 125000)]);
    });

    test('Rs without dot and LKR suffix', () {
      expect(p('SUGAR Rs 310.00').items.single.amountCents, 31000);
      expect(p('SALT 120.00 LKR').items.single.amountCents, 12000);
    });

    test('comma read as decimal point by OCR', () {
      expect(p('TEA 450,00').items.single.amountCents, 45000);
    });

    test('letter O read instead of zero', () {
      expect(p('DHAL 1,15O.OO').items.single.amountCents, 115000);
    });

    test('trailing minus means negative', () {
      expect(p('PROMO 25.00-').items.single.amountCents, -2500);
    });

    test('a 3-decimal quantity is not mistaken for a price', () {
      expect(p('CARROT 0.500 400.00 200.00').items.single.amountCents, 20000);
    });

    test('decimal quantity times unit price rounds to the cent', () {
      // 0.333 x 100.00 = 33.30
      expect(p('BEANS 0.333 x 100.00').items.single.amountCents, 3330);
    });

    test('whole numbers without decimals are not prices', () {
      expect(p('MEMBER 12345').items, isEmpty);
    });
  });

  group('totals', () {
    test('NET TOTAL beats SUB TOTAL', () {
      expect(p('TEA 10.00\nSUB TOTAL 10.00\nNET TOTAL 9.00').totalCents, 900);
    });

    test('GRAND TOTAL beats TOTAL', () {
      expect(p('TEA 10.00\nTOTAL 10.00\nGRAND TOTAL 11.00').totalCents, 1100);
    });

    test('only SUB TOTAL present is used', () {
      expect(p('TEA 10.00\nSUBTOTAL 10.00').totalCents, 1000);
    });

    test('TOTAL SAVINGS is not the total', () {
      final r = p('TEA 10.00\nTOTAL SAVINGS 2.00\nTOTAL 10.00');
      expect(r.totalCents, 1000);
      expect(r.items.length, 1);
    });

    test('no total line gives null', () {
      expect(p('TEA 10.00').totalCents, isNull);
    });

    test('total lines are never items', () {
      expect(p('TEA 10.00\nTOTAL 10.00').items.length, 1);
    });
  });

  group('ignored lines', () {
    test('payment section is ignored', () {
      final r = p('TEA 10.00\nCASH 100.00\nBUN 5.00\nBALANCE 90.00');
      expect(r.items, const [ParsedItem('TEA', 1000)]);
    });

    test('lines after TOTAL are not items', () {
      expect(p('TEA 10.00\nTOTAL 10.00\nTHANK YOU 1.00').items.length, 1);
    });

    test('tax and header lines are skipped', () {
      expect(p('VAT 18% 15.00\nITEM QTY AMOUNT\nTEA 10.00').items, const [ParsedItem('TEA', 1000)]);
    });

    test('numbers-only detail row under a priced item is not a new item', () {
      expect(p('CRACKER 450.00\n2 x 225.00').items, const [ParsedItem('CRACKER', 45000)]);
    });

    test('empty text', () {
      final r = p('');
      expect(r.items, isEmpty);
      expect(r.storeName, isNull);
      expect(r.date, isNull);
    });
  });

  group('dates', () {
    test('dd/mm/yyyy', () => expect(p('12/01/2026').date, DateTime(2026, 1, 12)));
    test('ISO yyyy-mm-dd', () => expect(p('2026-03-04').date, DateTime(2026, 3, 4)));
    test('invalid month is skipped', () => expect(p('12/13/2026').date, isNull));
  });

  group('OcrService.groupIntoRows', () {
    // Simulates ML Kit returning the names column and the prices column
    // as separate blocks.
    test('joins name and price fragments on the same row, left to right', () {
      final rows = OcrService.groupIntoRows(const [
        OcrFragment('450.00', Rect.fromLTWH(300, 100, 60, 20)),
        OcrFragment('180.00', Rect.fromLTWH(300, 131, 60, 20)),
        OcrFragment('MILK', Rect.fromLTWH(10, 102, 80, 20)),
        OcrFragment('BREAD', Rect.fromLTWH(10, 130, 80, 20)),
      ]);
      expect(rows, 'MILK  450.00\nBREAD  180.00');
    });

    test('empty input', () => expect(OcrService.groupIntoRows(const []), ''));
  });
}
