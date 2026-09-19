import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';

Widget _appWithDb(AppDatabase db) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const CorplexApp(),
  );
}

/// Disposing a drift stream query schedules a zero-duration Timer to mark
/// itself closed. If left to flutter_test's automatic teardown, that timer
/// has no chance to fire before the framework's `!timersPending` check
/// runs. Tearing the tree down ourselves and pumping once first flushes it.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // A duration, even a small one, is required to make FakeAsync actually
  // elapse and fire the zero-duration timer scheduled during disposal.
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase db;

  setUp(() {
    // TextField's cursor blink uses a periodic Timer; without this it's
    // still armed when a test ends and trips flutter_test's timer check.
    EditableText.debugDeterministicCursor = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  testWidgets('App launches on Notes tab and can switch to Library', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();

    expect(
      find.text('No notes yet.\nTap + to capture your first one.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(
      find.text('Papers you reference in notes will show up here.'),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('creating a note from the FAB shows it in the list', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'My first paper notes');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('My first paper notes'), findsOneWidget);

    await _disposeTree(tester);
  });
}
