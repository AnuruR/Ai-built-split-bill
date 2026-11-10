/// How a shared item is divided between the people assigned to it.
enum SplitMethod {
  /// Everyone pays the same; leftover cents go to the first person.
  equal,

  /// The user types each person's exact amount; must add up to the item.
  exact,

  /// Each person pays a percentage; percentages must add up to 100.
  percentage;

  static SplitMethod fromName(String? name) =>
      SplitMethod.values.firstWhere((m) => m.name == name, orElse: () => SplitMethod.equal);
}
