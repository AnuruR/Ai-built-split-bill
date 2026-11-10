import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/providers/draft_receipt_provider.dart';
import 'package:snapsplit/providers/receipts_provider.dart';
import 'package:snapsplit/providers/service_providers.dart';
import 'package:snapsplit/services/receipt_repository.dart';
import 'package:snapsplit/services/split_calculator.dart';

void main() {
  late ProviderContainer c;
  late InMemoryReceiptRepository repo;

  final saved = Receipt(
    id: 'r1',
    storeName: 'KEELLS',
    date: DateTime(2026, 11, 1),
    totalCents: 1000,
    items: const [ReceiptItem(id: 'i1', name: 'RICE', amountCents: 1000, personIds: ['a', 'b'])],
  );

  setUp(() async {
    repo = InMemoryReceiptRepository();
    await repo.save(saved);
    c = ProviderContainer(overrides: [receiptRepositoryProvider.overrideWithValue(repo)]);
  });
  tearDown(() => c.dispose());

  test('loads saved receipts', () async {
    expect((await c.read(receiptsProvider.future)).single.id, 'r1');
  });

  test('delete removes it from the list and the repository', () async {
    await c.read(receiptsProvider.future);
    await c.read(receiptsProvider.notifier).delete('r1');
    expect(c.read(receiptsProvider).value, isEmpty);
    expect(await repo.fetchById('r1'), isNull);
  });

  test('edit and recalculate (FR-13): same id, new split replaces the old one', () async {
    final draft = c.read(draftReceiptProvider.notifier);
    draft.startEditing(saved);
    expect(draft.editingSaved, isTrue);

    // Change the amount and the split, as the user would on S03/S04.
    draft.updateItem('i1', amountCents: 1201);
    draft.setPeople('i1', ['a', 'b', 'c']);
    final edited = c.read(draftReceiptProvider)!;

    await repo.save(edited);
    c.invalidate(receiptsProvider);
    final list = await c.read(receiptsProvider.future);

    expect(list.length, 1); // replaced, not duplicated
    expect(list.single.id, 'r1');
    expect(SplitCalculator.summarize(list.single.items).perPerson, {'a': 401, 'b': 400, 'c': 400});
  });

  test('starting a new scan clears the editing flag', () {
    final draft = c.read(draftReceiptProvider.notifier);
    draft.startEditing(saved);
    draft.startEmpty();
    expect(draft.editingSaved, isFalse);
  });
}
