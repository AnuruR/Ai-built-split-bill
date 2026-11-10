import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:snapsplit/providers/draft_receipt_provider.dart';
import 'package:snapsplit/screens/review_screen.dart';
import 'package:snapsplit/services/receipt_parser.dart';
import 'package:snapsplit/widgets/item_edit_dialog.dart';

/// Widget tests: build the real screen in a fake environment and tap it.
void main() {
  Future<ProviderContainer> pumpReview(WidgetTester tester, ParsedReceipt parsed) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(draftReceiptProvider.notifier).startFromParsed(parsed);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ReviewScreen()),
    ));
    return container;
  }

  testWidgets('shows a match when items equal the total', (tester) async {
    await pumpReview(tester, const ParsedReceipt(items: [ParsedItem('MILK', 45000)], totalCents: 45000));
    expect(find.text('MILK'), findsOneWidget);
    expect(find.text('Items match the receipt total'), findsOneWidget);
  });

  testWidgets('warns about a missing amount', (tester) async {
    await pumpReview(tester, const ParsedReceipt(items: [ParsedItem('MILK', 45000)], totalCents: 50000));
    expect(find.textContaining('Rs. 50.00 missing'), findsOneWidget);
  });

  testWidgets('adding an item via the dialog fixes the mismatch', (tester) async {
    final c = await pumpReview(
        tester, const ParsedReceipt(items: [ParsedItem('MILK', 45000)], totalCents: 50000));
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('itemName')), 'Bag');
    await tester.enterText(find.byKey(const Key('itemAmount')), '50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.read(draftReceiptProvider)!.items.length, 2);
    expect(find.text('Items match the receipt total'), findsOneWidget);
  });

  testWidgets('dialog rejects an empty name and a bad amount', (tester) async {
    await pumpReview(tester, const ParsedReceipt(items: [ParsedItem('MILK', 100)], totalCents: 100));
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('itemAmount')), '1.2.3');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter an amount like 250.00'), findsOneWidget);
  });

  group('validators', () {
    test('name', () {
      expect(validateItemName(' '), isNotNull);
      expect(validateItemName('Milk'), isNull);
    });
    test('amount', () {
      expect(validateAmount('0'), isNotNull);
      expect(validateAmount('abc'), isNotNull);
      expect(validateAmount('-50.00'), isNull); // discount
      expect(validateAmount('1,250.00'), isNull);
    });
  });

  group('limits', () {
    test('amount upper bound (Rs. 10,000,000)', () {
      expect(validateAmount('10,000,000.00'), isNull);
      expect(validateAmount('10,000,000.01'), isNotNull);
      expect(validateAmount('-10,000,000.01'), isNotNull);
    });
    test('item name length', () {
      expect(validateItemName('a' * maxItemNameLength), isNull);
      expect(validateItemName('a' * (maxItemNameLength + 1)), isNotNull);
    });
  });

  testWidgets('Back on a receipt with items asks before discarding', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(draftReceiptProvider.notifier)
        .startFromParsed(const ParsedReceipt(items: [ParsedItem('MILK', 100)], totalCents: 100));
    // A tiny router with a page underneath, so "Back" has somewhere to go.
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('HOME'))),
      GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/review'); // Home underneath, Review on top
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute(); // the Android Back button
    await tester.pumpAndSettle();
    expect(find.text('Discard this receipt?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('MILK'), findsOneWidget); // still here
    expect(c.read(draftReceiptProvider), isNotNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(c.read(draftReceiptProvider), isNull); // draft cleared
    expect(find.text('HOME'), findsOneWidget); // and we went back
  });
}
