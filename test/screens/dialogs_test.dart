import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/providers/people_provider.dart';
import 'package:snapsplit/screens/people_screen.dart';
import 'package:snapsplit/services/people_repository.dart';

/// Regression test for the red error screen when adding a person:
/// the dialog's TextEditingController was disposed while the closing
/// animation still used it. pumpAndSettle runs that animation to the end,
/// and the test fails if any exception is thrown during it.
/// PeopleScreen with an in-memory repository instead of Supabase.
Widget _app() => ProviderScope(
      overrides: [peopleRepositoryProvider.overrideWithValue(InMemoryPeopleRepository())],
      child: const MaterialApp(home: PeopleScreen()),
    );

void main() {
  testWidgets('adding two people in a row does not crash', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    for (final name in ['Amal', 'Bimal']) {
      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('personName')), name);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Amal'), findsOneWidget);
    expect(find.text('Bimal'), findsOneWidget);
  });

  testWidgets('duplicate name shows an error and keeps the dialog open', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personName')), 'me'); // "Me" exists
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Someone with that name already exists'), findsOneWidget);
  });

}
