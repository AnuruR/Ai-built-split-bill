import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/providers/draft_receipt_provider.dart';
import 'package:snapsplit/services/receipt_parser.dart';

void main() {
  // A ProviderContainer runs providers without any widgets – ideal for tests.
  late ProviderContainer container;
  DraftReceiptNotifier notifier() => container.read(draftReceiptProvider.notifier);

  setUp(() {
    container = ProviderContainer();
    notifier().startFromParsed(const ParsedReceipt(
      storeName: 'KEELLS',
      items: [ParsedItem('MILK', 45000), ParsedItem('BREAD', 18000)],
      totalCents: 63000,
    ));
  });
  tearDown(() => container.dispose());

  test('starts from parsed data', () {
    final r = container.read(draftReceiptProvider)!;
    expect(r.items.map((i) => i.name), ['MILK', 'BREAD']);
    expect(r.isReconciled, isTrue);
  });

  test('missing total falls back to the item sum', () {
    notifier().startFromParsed(const ParsedReceipt(items: [ParsedItem('TEA', 100)]));
    expect(container.read(draftReceiptProvider)!.totalCents, 100);
  });

  test('add, edit and delete keep the sum up to date', () {
    notifier().addItem('EGGS', 30000);
    var r = container.read(draftReceiptProvider)!;
    expect(r.itemsSumCents, 93000);
    expect(r.isReconciled, isFalse);

    notifier().updateItem(r.items.last.id, amountCents: 1000);
    r = container.read(draftReceiptProvider)!;
    expect(r.itemsSumCents, 64000);

    notifier().removeItem(r.items.last.id);
    expect(container.read(draftReceiptProvider)!.isReconciled, isTrue);
  });

  test('restoreItem puts the item back at the same position with the same id', () {
    final milk = container.read(draftReceiptProvider)!.items.first;
    notifier().removeItem(milk.id);
    notifier().restoreItem(milk, 0);
    expect(container.read(draftReceiptProvider)!.items.first.id, milk.id);
  });

  test('updateHeader changes only the given fields', () {
    notifier().updateHeader(totalCents: 1);
    final r = container.read(draftReceiptProvider)!;
    expect(r.totalCents, 1);
    expect(r.storeName, 'KEELLS');
  });
}
