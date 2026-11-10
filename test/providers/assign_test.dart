import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/providers/draft_receipt_provider.dart';
import 'package:snapsplit/providers/people_provider.dart';
import 'package:snapsplit/screens/assign_screen.dart' show splitError;
import 'package:snapsplit/services/people_repository.dart';
import 'package:snapsplit/services/receipt_parser.dart';

void main() {
  late ProviderContainer c;
  DraftReceiptNotifier draft() => c.read(draftReceiptProvider.notifier);
  ReceiptItem item() => c.read(draftReceiptProvider)!.items.first;

  setUp(() {
    c = ProviderContainer();
    draft().startFromParsed(const ParsedReceipt(items: [ParsedItem('MILK', 1000)]));
  });
  tearDown(() => c.dispose());

  group('draft assignment', () {
    test('OCR items get a suggested category', () => expect(item().categoryId, 'dairy'));

    test('togglePerson adds and removes', () {
      draft().togglePerson(item().id, 'a');
      draft().togglePerson(item().id, 'b');
      expect(item().personIds, ['a', 'b']);
      draft().togglePerson(item().id, 'a');
      expect(item().personIds, ['b']);
    });

    test('switching to exact gives valid even shares', () {
      draft().setPeople(item().id, ['a', 'b', 'c']);
      draft().setMethod(item().id, SplitMethod.exact);
      expect(item().shares, {'a': 334, 'b': 333, 'c': 333});
      expect(splitError(item()), isNull);
    });

    test('switching to percentage gives shares summing to 100%', () {
      draft().setPeople(item().id, ['a', 'b', 'c']);
      draft().setMethod(item().id, SplitMethod.percentage);
      expect(item().shares, {'a': 3334, 'b': 3333, 'c': 3333});
      expect(splitError(item()), isNull);
    });

    test('a bad share is reported by splitError', () {
      draft().setPeople(item().id, ['a', 'b']);
      draft().setMethod(item().id, SplitMethod.exact);
      draft().setShare(item().id, 'a', 900);
      expect(splitError(item()), isNotNull);
    });

    test('unassigned is not an error', () => expect(splitError(item()), isNull));

    test('assignUnassigned only touches items without people', () {
      draft().addItem('BREAD', 500);
      draft().setPeople(item().id, ['a']);
      draft().assignUnassigned(['a', 'b']);
      final items = c.read(draftReceiptProvider)!.items;
      expect(items[0].personIds, ['a']);
      expect(items[1].personIds, ['a', 'b']);
    });

    test('removePersonEverywhere resets shares', () {
      draft().setPeople(item().id, ['a', 'b']);
      draft().setMethod(item().id, SplitMethod.exact);
      draft().removePersonEverywhere('b');
      expect(item().personIds, ['a']);
      expect(item().shares, {'a': 1000});
    });

    test('changing the amount keeps exact shares valid', () {
      draft().setPeople(item().id, ['a', 'b']);
      draft().setMethod(item().id, SplitMethod.exact);
      draft().updateItem(item().id, amountCents: 2001);
      expect(splitError(item()), isNull);
    });
  });

  group('people', () {
    late ProviderContainer pc;
    setUp(() {
      pc = ProviderContainer(overrides: [
        // Swap the real repository for a fresh in-memory one.
        peopleRepositoryProvider.overrideWithValue(
            InMemoryPeopleRepository([const Person(id: '1', name: 'Amal')])),
      ]);
    });
    tearDown(() => pc.dispose());

    test('loads, adds, renames, removes', () async {
      final n = pc.read(peopleProvider.notifier);
      expect((await pc.read(peopleProvider.future)).map((p) => p.name), ['Amal']);
      final b = await n.add('  Bimal ');
      expect(b.name, 'Bimal');
      await n.rename(b.id, 'Bimali');
      await n.remove('1');
      expect(pc.read(peopleProvider).value!.map((p) => p.name), ['Bimali']);
    });

    test('name validation', () async {
      await pc.read(peopleProvider.future);
      final n = pc.read(peopleProvider.notifier);
      expect(n.validateName(''), isNotNull);
      expect(n.validateName('amal'), isNotNull); // duplicate, case-insensitive
      expect(n.validateName('Amal', exceptId: '1'), isNull); // renaming yourself
      expect(n.validateName('Chathu'), isNull);
    });
  });
}
