import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/category.dart';
import 'package:snapsplit/services/category_suggester.dart';

void main() {
  String s(String name) => CategorySuggester.suggest(name);

  test('common Sri Lankan supermarket items', () {
    expect(s('ANCHOR MILK POWDER 400G'), 'dairy');
    expect(s('KOTMALE FRESH MILK 1L'), 'dairy');
    expect(s('SANDWICH BREAD'), 'bakery');
    expect(s('BANANA AMBUL'), 'produce');
    expect(s('MUNCHEE CRACKER'), 'snacks');
    expect(s('SUNLIGHT SOAP'), 'household');
    expect(s('SIGNAL TOOTHPASTE'), 'personal_care');
    expect(s('KEERI SAMBA 5KG'), 'groceries');
    expect(s('MYSORE DHAL 1KG'), 'groceries');
    expect(s('CHICKEN BREAST'), 'meat_fish');
    expect(s('DILMAH TEA 100G'), 'beverages');
  });

  test('rule order: specific rules win over general ones', () {
    expect(s('Vegetable Fried Rice'), 'dining'); // not produce or groceries
    expect(s('MALIBAN MILK BISCUIT'), 'snacks'); // not dairy
    expect(s('CHICKEN BURGER'), 'dining'); // not meat
  });

  test('keywords match at word starts only', () {
    expect(s('STEAK'), 'other'); // contains "tea" but not as a word
    expect(s('BISCUITS'), 'snacks'); // plural still matches
  });

  test('case-insensitive', () => expect(s('fresh milk'), 'dairy'));

  test('unknown or empty gives other', () {
    expect(s('XYZ 123'), 'other');
    expect(s(''), 'other');
  });

  test('every suggestion is a real category', () {
    final ids = Category.defaults.map((c) => c.id).toSet();
    for (final n in ['MILK', 'BREAD', 'SOAP', 'RICE', 'unknown', 'KOTTU']) {
      expect(ids, contains(s(n)));
    }
  });
}
