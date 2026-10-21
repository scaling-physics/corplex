import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/search/saved_searches.dart';
import 'package:corplex/features/search/search_screen.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

void main() {
  late AppDatabase db;

  setUpAll(loadMacFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Pinned cortex'),
            pinned: const Value(true),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n2'),
            title: const Value('Loose cortex'),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  testWidgets('Saved Searches section appears once one exists and runs it', (
    tester,
  ) async {
    useMacWindow(tester, macWindowSizes['laptop16']!);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(
            const NoShareIntentSource(),
          ),
        ],
        child: const CorplexApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved Searches'), findsNothing);

    final id = await createSavedSearch(
      db,
      name: 'Pinned cortex notes',
      query: 'cortex is:pinned',
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved Searches'), findsOneWidget);
    final row = find.byKey(ValueKey('mac-saved-search-$id'));
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsView), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('mac-toolbar-search')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'cortex is:pinned',
    );
    expect(
      find.descendant(
        of: find.byType(SearchResultsView),
        matching: find.textContaining('Pinned cortex', findRichText: true),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(SearchResultsView),
        matching: find.textContaining('Loose cortex', findRichText: true),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }, variant: macOnly);
}
