import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/gestures.dart';
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
    await db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(id: const Value('read'), name: 'Reading'),
        );
    for (final (id, title, folder) in [
      ('n1', 'Spike sorting', 'lab'),
      ('n2', 'Rig notes', 'lab'),
      ('n3', 'Friston 2010', 'read'),
      ('n4', 'Loose thought', null),
    ]) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value(title),
              folderId: Value(folder),
            ),
          );
    }
    await db
        .into(db.projects)
        .insert(ProjectsCompanion.insert(id: const Value('p'), name: 'Thesis'));
    await db
        .into(db.projectNotes)
        .insert(ProjectNotesCompanion.insert(projectId: 'p', noteId: 'n3'));
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: const Value('t'), name: 'mPFC'));
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

  testWidgets('folders, projects and tags in the sidebar, with counts', (
    tester,
  ) async {
    await show(tester);
    expect(
      find.descendant(of: row('mac-all-notes'), matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('mac-folder-lab'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('mac-project-p'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(row('mac-tag-t'), findsOneWidget);
    // The chip row is redundant beside the sidebar.
    expect(find.byType(ChoiceChip), findsNothing);
    expect(listTitle(tester), 'Notes');

    await tester.tap(row('mac-folder-lab'));
    await tester.pumpAndSettle();
    expect(listTitle(tester), 'Lab');
    expect(find.text('Spike sorting'), findsOneWidget);
    expect(find.text('Friston 2010'), findsNothing);

    await tester.tap(row('mac-project-p'));
    await tester.pumpAndSettle();
    expect(listTitle(tester), 'Thesis');
    expect(find.text('Friston 2010'), findsOneWidget);
    expect(find.text('Spike sorting'), findsNothing);

    await tester.tap(row('mac-tag-t'));
    await tester.pumpAndSettle();
    expect(listTitle(tester), '#mPFC');

    await tester.tap(row('mac-all-notes'));
    await tester.pumpAndSettle();
    expect(find.text('Loose thought'), findsOneWidget);

    // Folding a section hides its rows.
    await tester.tap(find.text('Notes').first);
    await tester.pumpAndSettle();
    expect(row('mac-folder-lab'), findsNothing);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('drag a note onto a folder, a project or a tag', (tester) async {
    await show(tester);
    Future<void> drag(String title, String target) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(title)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(row(target)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await drag('Loose thought', 'mac-folder-read');
    await drag('Rig notes', 'mac-project-p');
    await drag('Spike sorting', 'mac-tag-t');
    await tester.runAsync(() async {
      final n4 = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('n4'))).getSingle();
      expect(n4.folderId, 'read');
      final inProject = await db.select(db.projectNotes).get();
      expect(inProject.map((r) => r.noteId).toSet(), {'n2', 'n3'});
      final tagged = await db.select(db.noteTags).get();
      expect(tagged.map((r) => r.noteId), ['n1']);
    });
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row('mac-folder-read'), matching: find.text('2')),
      findsOneWidget,
    );
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('New Folder, rename and delete from the sidebar', (tester) async {
    await show(tester);
    await tester.tap(row('mac-new-folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Grants');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(listTitle(tester), 'Grants');

    await tester.tap(row('mac-folder-lab'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename Folder…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Lab book');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: row('mac-folder-lab'),
        matching: find.text('Lab book'),
      ),
      findsOneWidget,
    );

    await tester.tap(row('mac-folder-lab'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Folder…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(row('mac-folder-lab'), findsNothing);
    // Its notes are unfiled, not deleted.
    expect(
      find.descendant(of: row('mac-all-notes'), matching: find.text('4')),
      findsOneWidget,
    );
    await dispose(tester);
  }, variant: macOnly);
}
