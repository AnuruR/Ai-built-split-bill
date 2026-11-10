/// Someone a bill can be split with. Belongs to the signed-in user
/// (the user's own "contacts" list), so the same people can be reused.
class Person {
  final String id;
  final String name;

  const Person({required this.id, required this.name});

  factory Person.fromMap(Map<String, dynamic> map) =>
      Person(id: map['id'] as String, name: map['name'] as String);

  /// `user_id` is filled in by the service layer when saving.
  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  Person copyWith({String? name}) => Person(id: id, name: name ?? this.name);

  @override
  bool operator ==(Object other) => other is Person && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
