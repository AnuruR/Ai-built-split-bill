import '../utils/money.dart';

/// One item line found on a receipt.
class ParsedItem {
  final String name;
  final Cents amountCents;
  const ParsedItem(this.name, this.amountCents);

  @override
  String toString() => 'ParsedItem($name, $amountCents)';
  @override
  bool operator ==(Object other) =>
      other is ParsedItem && other.name == name && other.amountCents == amountCents;
  @override
  int get hashCode => Object.hash(name, amountCents);
}

/// Everything the parser could extract. Any field may be missing – the user
/// fixes it on the review screen.
class ParsedReceipt {
  final String? storeName;
  final DateTime? date;
  final List<ParsedItem> items;

  /// The total printed on the receipt, if a TOTAL line was found.
  final Cents? totalCents;

  const ParsedReceipt({this.storeName, this.date, this.items = const [], this.totalCents});
}

/// Turns OCR text (one receipt row per line) into items, total, store and date.
///
/// It is a pure function of the text, so it is unit tested with sample
/// receipts in test/services/receipt_parser_test.dart.
///
/// Rules, in order, for each line:
///  1. Lines after the payment section starts (CASH, BALANCE, CARD...) are ignored.
///  2. TOTAL-like lines set the total (NET TOTAL > GRAND TOTAL > TOTAL > SUB TOTAL).
///  3. Other non-item lines (tax, savings, headers) are skipped.
///  4. A line ending in a price is an item; the LAST price on the line is the
///     line amount, so "MILK 2 225.00 450.00" -> 450.00.
///  5. "2 x 225.00" with no line amount -> quantity x unit price.
///  6. A text-only line followed by a numbers-only line (Keells puts long
///     names on their own row) is joined into one item.
class ReceiptParser {
  const ReceiptParser._();

  // A price: digits with optional thousands commas, then a 2-digit decimal
  // part (".", or "," which OCR sometimes produces). The lookarounds stop it
  // matching inside "1.000" (a quantity) or long barcodes.
  static final _price = RegExp(r'(?<![\d.,])(-?)(\d{1,3}(?:,\d{3})+|\d+)[.,](\d{2})(?![\d.,]*\d)(-?)');

  // "2 x 225.00", "2 @ 225.00", "0.500 X 1,200.00"
  static final _qtyTimesPrice =
      RegExp(r'(\d+(?:\.\d{1,3})?)\s*[xX@*]\s*(\d{1,3}(?:,\d{3})+|\d+)[.,](\d{2})\s*$');

  static final _hasLetters = RegExp(r'[A-Za-z]{2,}');

  static final _paymentWords = RegExp(
      r'\b(CASH|BALANCE|CHANGE|TENDER(ED)?|CARD|VISA|MASTER|AMEX|PAID|PAYMENT|LOYALTY|NEXUS)\b',
      caseSensitive: false);

  static final _skipWords = RegExp(
      r'\b(VAT|TAX|SSCL|SAVINGS?|SAVED|NO\.? ?OF ITEMS|ITEMS?\s*COUNT|QTY|INVOICE|BILL\s*NO|CASHIER|TEL|PHONE)\b',
      caseSensitive: false);

  static final _storeNames = RegExp(
      r'KEELLS|CARGILLS|FOOD\s*CITY|ARPICO|GLOMARK|LAUGFS|SPAR|SATHOSA',
      caseSensitive: false);

  /// Parses OCR text. [text] should have one receipt row per line – see
  /// OcrService.groupIntoRows for how that is achieved from ML Kit output.
  static ParsedReceipt parse(String text) {
    final lines = text
        .split('\n')
        .map((l) => _fixOcrDigits(l.replaceAll(RegExp(r'\bRs\.?\s*|\bLKR\b', caseSensitive: false), ' '))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final items = <ParsedItem>[];
    final totals = <int, Cents>{}; // priority -> amount
    String? pendingName;
    var inPayment = false;

    for (final line in lines) {
      if (_paymentWords.hasMatch(line)) inPayment = true;
      if (inPayment) continue;

      final totalPriority = _totalPriority(line);
      if (totalPriority != null) {
        final amount = _lastPrice(line);
        if (amount != null) totals.putIfAbsent(totalPriority, () => amount);
        pendingName = null;
        continue;
      }
      // Once a real TOTAL is seen, nothing after it is an item.
      if (totals.keys.any((p) => p >= 2)) continue;

      if (_skipWords.hasMatch(line) || _isDateLine(line)) {
        pendingName = null;
        continue;
      }

      final amount = _lineAmount(line);
      final name = _cleanName(line);

      if (amount == null) {
        // Text without a price: possibly the name row of a two-row item.
        pendingName = _hasLetters.hasMatch(line) ? name : null;
        continue;
      }
      if (amount == 0) {
        // "DISCOUNT 0.00", "SERVICE CHARGE 0.00": nothing to split.
        pendingName = null;
        continue;
      }
      if (name.isNotEmpty) {
        items.add(ParsedItem(name, amount));
      } else if (pendingName != null) {
        items.add(ParsedItem(pendingName, amount));
      }
      // A numbers-only line with no pending name is a detail row
      // (e.g. "2 x 225.00" under an item that already has its amount).
      pendingName = null;
    }

    Cents? total;
    for (final p in [4, 3, 2, 1]) {
      if (totals.containsKey(p)) {
        total = totals[p];
        break;
      }
    }

    return ParsedReceipt(
      storeName: _findStore(lines),
      date: _findDate(lines),
      items: items,
      totalCents: total,
    );
  }

  /// Returns a priority if the line is a total line, else null.
  static int? _totalPriority(String line) {
    final u = line.toUpperCase();
    if (!u.contains('TOTAL')) return null;
    if (RegExp(r'TOTAL\s*(ITEMS?|QTY|SAVINGS?|DISCOUNT)').hasMatch(u)) return null;
    if (RegExp(r'NET\s*TOTAL').hasMatch(u)) return 4;
    if (RegExp(r'GRAND\s*TOTAL').hasMatch(u)) return 3;
    if (RegExp(r'SUB\s*-?\s*TOTAL').hasMatch(u)) return 1;
    return 2;
  }

  /// The amount for an item line: "qty x unit" if that is how it ends,
  /// otherwise the last price on the line.
  static Cents? _lineAmount(String line) {
    final q = _qtyTimesPrice.firstMatch(line);
    if (q != null) {
      // Quantity in thousandths to support "0.500" kg without doubles.
      final qParts = q.group(1)!.split('.');
      final qtyMilli = int.parse(qParts[0]) * 1000 +
          (qParts.length > 1 ? int.parse(qParts[1].padRight(3, '0')) : 0);
      final unit = int.parse(q.group(2)!.replaceAll(',', '')) * 100 + int.parse(q.group(3)!);
      return (qtyMilli * unit + 500) ~/ 1000; // round half up to the cent
    }
    return _lastPrice(line);
  }

  static Cents? _lastPrice(String line) {
    final matches = _price.allMatches(line).toList();
    if (matches.isEmpty) return null;
    final m = matches.last;
    final value = int.parse(m.group(2)!.replaceAll(',', '')) * 100 + int.parse(m.group(3)!);
    final negative = m.group(1) == '-' || m.group(4) == '-' || line.contains('(${m.group(0)})');
    return negative ? -value : value;
  }

  /// Item name = the text before the first number column, without leading
  /// item codes (e.g. "001 " or "4791234567890 ").
  static String _cleanName(String line) {
    var s = line;
    final firstPrice = _price.firstMatch(s);
    final firstQty = _qtyTimesPrice.firstMatch(s);
    var cut = s.length;
    if (firstPrice != null) cut = firstPrice.start;
    if (firstQty != null && firstQty.start < cut) cut = firstQty.start;
    s = s.substring(0, cut);
    s = s.replaceFirst(RegExp(r'^\s*\d+\s+'), ''); // leading item code
    // Trailing quantity column, e.g. " 1" or " 3 @".
    s = s.replaceFirst(RegExp(r'(\s+\d+(\.\d+)?(\s*[xX@*])?)+\s*$'), '');
    // Trailing OCR junk tokens containing symbols, e.g. "*x", "#", "@".
    s = s.replaceFirst(RegExp(r'(\s+\S*[*@#|~]\S*)+\s*$'), '');
    s = s.replaceAll(RegExp(r'[\s\-:*]+$'), '').trim();
    return _hasLetters.hasMatch(s) ? s : '';
  }

  /// OCR often reads 0 as O and 1 as l/I inside numbers ("1,15O.00").
  /// Only tokens that already look like prices are fixed.
  static String _fixOcrDigits(String line) => line.replaceAllMapped(
        RegExp(r'(?<=^|\s)[\dOolI]+(?:,[\dOolI]{3})*[.,][\dOolI]{2}-?(?=\s|$)'),
        (m) {
          final t = m.group(0)!;
          if (!RegExp(r'\d').hasMatch(t)) return t;
          return t.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[lI]'), '1');
        },
      );

  static final _dateRe = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b|\b(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b');

  static bool _isDateLine(String line) => _dateRe.hasMatch(line);

  /// Sri Lankan receipts use day/month/year (or ISO year-month-day).
  static DateTime? _findDate(List<String> lines) {
    for (final l in lines) {
      final m = _dateRe.firstMatch(l);
      if (m == null) continue;
      int y, mo, d;
      if (m.group(4) != null) {
        y = int.parse(m.group(4)!);
        mo = int.parse(m.group(5)!);
        d = int.parse(m.group(6)!);
      } else {
        d = int.parse(m.group(1)!);
        mo = int.parse(m.group(2)!);
        y = int.parse(m.group(3)!);
        if (y < 100) y += 2000;
      }
      if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
      return DateTime(y, mo, d);
    }
    return null;
  }

  /// A known supermarket name anywhere near the top, otherwise the first
  /// line that has letters.
  static String? _findStore(List<String> lines) {
    final top = lines.take(6);
    for (final l in top) {
      final m = _storeNames.firstMatch(l);
      if (m != null) return l;
    }
    for (final l in top) {
      if (_hasLetters.hasMatch(l)) return l;
    }
    return null;
  }
}
