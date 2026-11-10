import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/providers/auth_provider.dart';
import 'package:snapsplit/providers/service_providers.dart';
import 'package:snapsplit/screens/history_screen.dart';
import 'package:snapsplit/services/receipt_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<Receipt> receipts) async {
    final repo = InMemoryReceiptRepository();
    for (final r in receipts) {
      await repo.save(r);
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        receiptRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith((ref) => Stream.value('u1')),
      ],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Receipt r(String id, String store, String item, String cat) => Receipt(
        id: id,
        storeName: store,
        date: DateTime(2026, 11, int.parse(id)),
        totalCents: 1000,
        items: [ReceiptItem(id: 'i$id', name: item, amountCents: 1000, categoryId: cat)],
      );

  testWidgets('empty history says so', (tester) async {
    await pump(tester, []);
    expect(find.text('No saved receipts yet.'), findsOneWidget);
  });

  testWidgets('search narrows the list and can be cleared', (tester) async {
    await pump(tester, [r('1', 'KEELLS', 'MILK', 'dairy'), r('2', 'CARGILLS', 'BREAD', 'bakery')]);
    expect(find.text('2 receipt(s)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bread'); // item name
    await tester.pumpAndSettle();
    expect(find.text('CARGILLS'), findsOneWidget);
    expect(find.text('KEELLS'), findsNothing);

    await tester.enterText(find.byType(TextField), 'arpico');
    await tester.pumpAndSettle();
    expect(find.text('No receipts match these filters.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('2 receipt(s)'), findsOneWidget);
  });

  testWidgets('category chip filters', (tester) async {
    await pump(tester, [r('1', 'KEELLS', 'MILK', 'dairy'), r('2', 'CARGILLS', 'BREAD', 'bakery')]);
    final chip = find.widgetWithText(ChoiceChip, 'Dairy & Eggs');
    await tester.ensureVisible(chip); // it is in a horizontal scroll row
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('KEELLS'), findsOneWidget);
    expect(find.text('CARGILLS'), findsNothing);
  });
}
