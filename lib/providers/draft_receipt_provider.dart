import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/category_suggester.dart';
import '../services/receipt_parser.dart';
import '../services/split_calculator.dart';

const _uuid = Uuid();

/// The receipt currently being created/edited, shared by S02 -> S05.
/// `null` means no receipt is in progress.
///
/// A Notifier owns a piece of state and exposes methods to change it.
/// Screens `ref.watch` the provider and rebuild when `state` is replaced.
class DraftReceiptNotifier extends Notifier<Receipt?> {
  @override
  Receipt? build() => null;

  /// True when the draft is a saved receipt being edited (FR-13), so the
  /// summary says "Update" and saving replaces the existing receipt.
  bool editingSaved = false;

  /// Loads a saved receipt for editing. It keeps its id, so saving again
  /// overwrites it (save_receipt replaces its items and assignments).
  void startEditing(Receipt saved) {
    editingSaved = true;
    state = saved;
  }

  /// Starts a draft from OCR results.
  void startFromParsed(ParsedReceipt parsed, {String? imagePath}) {
    editingSaved = false;
    final items = [
      for (final p in parsed.items)
        ReceiptItem(
          id: _uuid.v4(),
          name: p.name,
          amountCents: p.amountCents,
          categoryId: CategorySuggester.suggest(p.name),
        ),
    ];
    state = Receipt(
      id: _uuid.v4(),
      storeName: parsed.storeName ?? 'Unknown store',
      date: parsed.date ?? DateTime.now(),
      // If no total was found, fall back to the item sum; the user can edit it.
      totalCents: parsed.totalCents ?? items.fold(0, (s, i) => s + i.amountCents),
      imagePath: imagePath,
      items: items,
    );
  }

  /// Starts an empty draft for manual entry.
  void startEmpty() => startFromParsed(const ParsedReceipt());

  void clear() {
    editingSaved = false;
    state = null;
  }

  // ---- editing (S03) ----
  // Each method builds a NEW Receipt with copyWith instead of mutating the
  // old one. Riverpod notices the new object and rebuilds the screens.

  void updateHeader({String? storeName, DateTime? date, int? totalCents}) {
    final r = state;
    if (r == null) return;
    state = r.copyWith(storeName: storeName, date: date, totalCents: totalCents);
  }

  /// Adds a new item at the end (or at [index], used for "undo delete").
  void addItem(String name, int amountCents, {int? index}) {
    final r = state;
    if (r == null) return;
    final item = ReceiptItem(
      id: _uuid.v4(),
      name: name,
      amountCents: amountCents,
      categoryId: CategorySuggester.suggest(name),
    );
    final items = [...r.items];
    items.insert(index ?? items.length, item);
    state = r.copyWith(items: items);
  }

  /// Puts back an item exactly as it was (keeps its id and assignments).
  void restoreItem(ReceiptItem item, int index) {
    final r = state;
    if (r == null) return;
    state = r.copyWith(items: [...r.items]..insert(index.clamp(0, r.items.length), item));
  }

  void updateItem(String itemId, {String? name, int? amountCents}) {
    final r = state;
    if (r == null) return;
    state = r.copyWith(items: [
      for (final i in r.items)
        if (i.id == itemId)
          _withDefaultShares(i.copyWith(
            name: name,
            amountCents: amountCents,
            // Re-suggest only if the user never picked a category.
            categoryId: name != null && i.categoryId == 'other'
                ? CategorySuggester.suggest(name)
                : null,
          ))
        else
          i,
    ]);
  }

  // ---- categorize & assign (S04) ----

  void _updateItem(String itemId, ReceiptItem Function(ReceiptItem) change) {
    final r = state;
    if (r == null) return;
    state = r.copyWith(items: [for (final i in r.items) i.id == itemId ? change(i) : i]);
  }

  void setCategory(String itemId, String categoryId) =>
      _updateItem(itemId, (i) => i.copyWith(categoryId: categoryId));

  /// Sets who shares an item. Shares are reset to an even split so the
  /// item is always in a valid state after a change.
  void setPeople(String itemId, List<String> personIds) =>
      _updateItem(itemId, (i) => _withDefaultShares(i.copyWith(personIds: personIds)));

  void togglePerson(String itemId, String personId) => _updateItem(itemId, (i) {
        final ids = i.personIds.contains(personId)
            ? i.personIds.where((p) => p != personId).toList()
            : [...i.personIds, personId];
        return _withDefaultShares(i.copyWith(personIds: ids));
      });

  void setMethod(String itemId, SplitMethod method) =>
      _updateItem(itemId, (i) => _withDefaultShares(i.copyWith(method: method)));

  /// Stores one person's raw share (cents for exact, basis points for %).
  /// May temporarily be invalid while the user is typing; the screen shows
  /// the SplitCalculator error until the shares add up.
  void setShare(String itemId, String personId, int value) =>
      _updateItem(itemId, (i) => i.copyWith(shares: {...i.shares, personId: value}));

  /// Assigns every item that has nobody yet to [personIds], split equally.
  void assignUnassigned(List<String> personIds) {
    final r = state;
    if (r == null || personIds.isEmpty) return;
    state = r.copyWith(items: [
      for (final i in r.items)
        i.personIds.isEmpty ? _withDefaultShares(i.copyWith(personIds: personIds)) : i,
    ]);
  }

  /// Removes a person from every item (used when a person is deleted).
  void removePersonEverywhere(String personId) {
    final r = state;
    if (r == null) return;
    state = r.copyWith(items: [
      for (final i in r.items)
        i.personIds.contains(personId)
            ? _withDefaultShares(
                i.copyWith(personIds: i.personIds.where((p) => p != personId).toList()))
            : i,
    ]);
  }

  /// Even starting shares for exact/percentage, so switching method never
  /// leaves an item invalid. Equal split needs no shares.
  static ReceiptItem _withDefaultShares(ReceiptItem i) {
    if (i.personIds.isEmpty || i.method == SplitMethod.equal) {
      return i.copyWith(shares: const {});
    }
    final total = i.method == SplitMethod.exact ? i.amountCents : SplitCalculator.fullPercentBp;
    return i.copyWith(shares: SplitCalculator.equal(total, i.personIds));
  }

  void removeItem(String itemId) {
    final r = state;
    if (r == null) return;
    state = r.copyWith(items: r.items.where((i) => i.id != itemId).toList());
  }
}

final draftReceiptProvider =
    NotifierProvider<DraftReceiptNotifier, Receipt?>(DraftReceiptNotifier.new);
