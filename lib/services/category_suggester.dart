/// Suggests a category for an item name using keyword rules (FR-07).
///
/// Simple, offline and predictable – and the user can always change it.
/// Rules are checked IN ORDER and the first match wins, so more specific
/// rules come first: "Vegetable Fried Rice" must be Dining, not Fruit & Veg
/// or Groceries; "Milk Biscuit" must be Snacks, not Dairy.
class CategorySuggester {
  const CategorySuggester._();

  static final List<(String, List<String>)> _rules = [
    ('dining', [
      'fried rice', 'kottu', 'burger', 'pizza', 'biriyani', 'biryani', 'submarine',
      'rice and curry', 'rice & curry', 'hoppers', 'string hopper', 'devilled',
      'meal', 'combo', 'shawarma',
    ]),
    ('snacks', [
      'biscuit', 'cracker', 'munchee', 'maliban', 'chips', 'chocolate', 'wafer',
      'cookie', 'mixture', 'murukku', 'popcorn', 'kist', 'toffee', 'candy', 'sweet',
    ]),
    ('beverages', [
      'tea', 'coffee', 'nescafe', 'milo', 'soda', 'juice', 'water', 'coca', 'coke',
      'pepsi', 'sprite', 'fanta', 'nectar', 'cordial', 'drink', 'elephant house',
      'ginger beer', 'kist nectar', 'red bull',
    ]),
    ('dairy', [
      'milk', 'anchor', 'kotmale', 'highland', 'pelwatte', 'yoghurt', 'yogurt',
      'curd', 'cheese', 'butter', 'egg', 'ghee', 'cream',
    ]),
    ('bakery', ['bread', 'bun', 'cake', 'roll', 'pastry', 'paan', 'croissant', 'muffin']),
    ('meat_fish', [
      'chicken', 'fish', 'prawn', 'beef', 'pork', 'mutton', 'sausage', 'tuna',
      'sprat', 'sprats', 'salaya', 'mackerel', 'cuttle', 'crab', 'meat', 'bacon',
    ]),
    ('produce', [
      'banana', 'ambul', 'apple', 'orange', 'mango', 'papaya', 'pineapple', 'grape',
      'onion', 'potato', 'carrot', 'tomato', 'beans', 'cabbage', 'lime', 'leeks',
      'pumpkin', 'brinjal', 'cucumber', 'garlic', 'ginger', 'veg', 'fruit', 'gotukola',
    ]),
    ('personal_care', [
      'shampoo', 'toothpaste', 'tooth', 'signal', 'clogard', 'lotion', 'sanitary',
      'razor', 'deodorant', 'perfume', 'baby cream', 'face wash', 'conditioner',
    ]),
    ('household', [
      'soap', 'detergent', 'sunlight', 'surf', 'vim', 'tissue', 'harpic', 'bag',
      'cleaner', 'bleach', 'dishwash', 'mosquito', 'foil', 'battery', 'bulb',
    ]),
    ('groceries', [
      'rice', 'samba', 'nadu', 'keeri', 'dhal', 'dal', 'parippu', 'sugar', 'flour',
      'atta', 'salt', 'oil', 'noodle', 'pasta', 'spice', 'chilli', 'curry powder',
      'pepper', 'turmeric', 'soya', 'sauce', 'ketchup', 'jam', 'coconut', 'cereal',
    ]),
  ];

  // Built once: each keyword must start at a word boundary, so "tea"
  // matches "TEA 100G" but not "STEAK"; plurals ("BISCUITS") still match.
  static final List<(String, RegExp)> _compiled = [
    for (final (id, words) in _rules)
      (id, RegExp(r'\b(' + words.map(RegExp.escape).join('|') + r')', caseSensitive: false)),
  ];

  /// Returns a category id from Category.defaults; 'other' if nothing matches.
  static String suggest(String itemName) {
    for (final (id, re) in _compiled) {
      if (re.hasMatch(itemName)) return id;
    }
    return 'other';
  }
}
