import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/models/models.dart';
import 'package:snapsplit/providers/draft_receipt_provider.dart';
import 'package:snapsplit/providers/people_provider.dart';
import 'package:snapsplit/providers/service_providers.dart';
import 'package:snapsplit/screens/summary_screen.dart';
import 'package:snapsplit/services/people_repository.dart';
import 'package:snapsplit/services/receipt_parser.dart';
import 'package:snapsplit/services/receipt_repository.dart';

void main() {
  late ProviderContainer c;
  late InMemoryReceiptRepository repo;

  Future<void> pump(WidgetTester tester, {required int totalCents}) async {
    repo = InMemoryReceiptRepository();
    c = ProviderContainer(overrides: [
      receiptRepositoryProvider.overrideWithValue(repo),
      peopleRepositoryProvider.overrideWithValue(InMemoryPeopleRepository(const [
        Person(id: 'a', name: 'Amal'),
        Person(id: 'b', name: 'Bimal'),
      ])),
    ]);
    addTearDown(c.dispose);
    final d = c.read(draftReceiptProvider.notifier);
    d.startFromParsed(ParsedReceipt(
      storeName: 'KEELLS',
      items: const [ParsedItem('MILK', 100), ParsedItem('SOAP', 300)],
      totalCents: totalCents,
    ));
    d.assignUnassigned(['a', 'b']);
    await c.read(peopleProvider.future);
    // Summary uses go_router only after saving; a plain MaterialApp is enough
    // for these checks, so we don't press Save on a reconciled receipt here.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: SummaryScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows per-person totals with the remainder on the first person', (tester) async {
    await pump(tester, totalCents: 400);
    // MILK 100 -> 50/50, SOAP 300 -> 150/150
    expect(find.text('Amal'), findsOneWidget);
    expect(find.text('Rs. 2.00'), findsNWidgets(2));
    expect(find.text('Rs. 4.00'), findsOneWidget); // receipt total
  });

  testWidgets('shows per-category totals', (tester) async {
    await pump(tester, totalCents: 400);
    expect(find.text('Dairy & Eggs'), findsOneWidget);
    expect(find.text('Household'), findsOneWidget);
  });

  testWidgets('mismatched total shows a warning and asks before saving', (tester) async {
    await pump(tester, totalCents: 500);
    expect(find.textContaining('≠ receipt'), findsOneWidget);
    await tester.tap(find.text('Save receipt'));
    await tester.pumpAndSettle();
    expect(find.text("Totals don't match"), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(await repo.fetchAll(), isEmpty); // nothing saved
  });
}
