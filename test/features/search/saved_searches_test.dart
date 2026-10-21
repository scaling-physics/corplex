import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/search/saved_searches.dart';
import 'package:corplex/features/search/search_screen.dart';

import '../../support/l10n_app.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  group('providers', () {
    test('create, order, rename, delete, restore', () async {
      final a = await createSavedSearch(db, name: 'B first', query: 'tag:b');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await createSavedSearch(db, name: '  ', query: ' tag:a ');
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      container.listen(savedSearchesProvider, (_, _) {});

      Future<List<SavedSearchEntry>> current() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return container.read(savedSearchesProvider).requireValue;
      }

      var list = await current();
      // A blank name falls back to the (trimmed) query.
      expect(list.map((s) => s.name), ['B first', 'tag:a']);
      expect(list.last.query, 'tag:a');

      // A set position wins over creation order.
      await (db.update(db.savedSearches)..where((s) => s.id.equals(b))).write(
        const SavedSearchesCompanion(position: Value(0)),
      );
      list = await current();
      expect(list.map((s) => s.id), [b, a]);

      await renameSavedSearch(db, a, 'Renamed');
      await renameSavedSearch(db, a, '   '); // blank: ignored
      list = await current();
      expect(list.last.name, 'Renamed');

      final removed = list.last;
      await deleteSavedSearch(db, a);
      expect((await current()).map((s) => s.id), [b]);
      await restoreSavedSearch(db, removed);
      list = await current();
      expect(list.map((s) => s.id), [b, a]);
      expect(list.last.name, 'Renamed');
    });
  });

  group('SearchScreen', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: localizedApp(const SearchScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('tips show only without saved searches', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('search-tips')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-tips-body')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-tips')));
      await tester.pump();
      expect(find.textContaining('is:pinned'), findsOneWidget);

      await createSavedSearch(db, name: 'Pinned', query: 'is:pinned');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-tips')), findsNothing);
      expect(find.text('Saved searches'), findsOneWidget);
      await close(tester);
    });

    testWidgets('save a search, run it, rename and delete with undo', (
      tester,
    ) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Cortex pinned'),
              pinned: const Value(true),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n2'),
              title: const Value('Cortex loose'),
            ),
          );
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'cortex is:pinned');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cortex pinned'), findsWidgets);
      expect(find.textContaining('Cortex loose'), findsNothing);

      // Bookmark → dialog with the query as the default name.
      await tester.tap(find.byKey(const ValueKey('save-search')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('saved-search-name')))
            .controller!
            .text,
        'cortex is:pinned',
      );
      await tester.enterText(
        find.byKey(const ValueKey('saved-search-name')),
        'Pinned cortex',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Clear: the empty screen lists it; tapping runs it.
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Pinned cortex'), findsOneWidget);
      expect(find.text('cortex is:pinned'), findsOneWidget);
      await tester.tap(find.text('Pinned cortex'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'cortex is:pinned',
      );
      expect(find.textContaining('Cortex pinned'), findsWidgets);
      expect(find.textContaining('Cortex loose'), findsNothing);

      // Back to the list; long-press → Rename.
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Pinned cortex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('saved-search-name')),
        'Mine',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Mine'), findsOneWidget);

      // Delete, then Undo.
      await tester.longPress(find.text('Mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Mine'), findsNothing);
      expect(find.textContaining('Deleted'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Mine'), findsOneWidget);
      await close(tester);
    });
  });
}
