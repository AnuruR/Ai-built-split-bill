/// A spending category (Groceries, Dairy, ...).
///
/// Categories are a fixed, shared list (seeded in the database in Phase 7),
/// so they are identified by a stable string [id] rather than a UUID.
class Category {
  final String id;
  final String name;

  const Category({required this.id, required this.name});

  factory Category.fromMap(Map<String, dynamic> map) =>
      Category(id: map['id'] as String, name: map['name'] as String);

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  /// Default categories. Kept in code too so the app works before the
  /// categories are loaded and so the category suggester can reference them.
  static const List<Category> defaults = [
    Category(id: 'groceries', name: 'Groceries'),
    Category(id: 'produce', name: 'Fruit & Veg'),
    Category(id: 'meat_fish', name: 'Meat & Fish'),
    Category(id: 'dairy', name: 'Dairy & Eggs'),
    Category(id: 'bakery', name: 'Bakery'),
    Category(id: 'beverages', name: 'Beverages'),
    Category(id: 'snacks', name: 'Snacks'),
    Category(id: 'dining', name: 'Food & Dining'),
    Category(id: 'household', name: 'Household'),
    Category(id: 'personal_care', name: 'Personal Care'),
    Category(id: 'other', name: 'Other'),
  ];

  static Category byId(String id) =>
      defaults.firstWhere((c) => c.id == id, orElse: () => defaults.last);

  @override
  bool operator ==(Object other) => other is Category && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
