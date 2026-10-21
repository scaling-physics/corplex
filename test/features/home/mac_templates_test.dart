import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
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
        .into(db.folders)
        .insert(FoldersCompanion.insert(id: const Value('lab'), name: 'Lab'));
    for (final (id, title, folder, template) in [
      ('n1', 'Spike sorting', 'lab', false),
      ('n2', 'Loose thought', null, false),
      ('tpl', 'Weekly review', 'lab', true),
    ]) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value(title),
              folderId: Value(folder),
              isTemplate: Value(template),
            ),
          );
    }
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> show(WidgetTester tester) async {
    useMacWindow(tester, macWindowSizes['laptop13']!);
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
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder row(String key) => find.byKey(ValueKey(key));
  String listTitle(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('mac-list-title'))).data!;

  testWidgets('Templates row appears with a template, apart from the lists', (
    tester,
  ) async {
    await show(tester);
    expect(row('mac-templates'), findsOneWidget);
    // Not in All Notes, nor in its folder's count.
    expect(find.text('Weekly review'), findsNothing);
    expect(
      find.descendant(of: row('mac-all-notes'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('mac-folder-lab'), matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(row('mac-templates'));
    await tester.pumpAndSettle();
    expect(listTitle(tester), 'Templates');
    expect(find.text('Weekly review'), findsWidgets);
    expect(find.text('Spike sorting'), findsNothing);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('no Templates row without a template', (tester) async {
    await db
        .update(db.notes)
        .write(const NotesCompanion(isTemplate: Value(false)));
    await show(tester);
    expect(row('mac-templates'), findsNothing);
    await dispose(tester);
  }, variant: macOnly);
}
