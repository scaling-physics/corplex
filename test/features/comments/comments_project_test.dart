import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/projects/project_page.dart';
import 'package:corplex/features/projects/projects_providers.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_audio_engine.dart';

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

  Future<String> seed() async {
    final id = await findOrCreateProject(db, 'Thesis');
    for (final n in ['n1', 'n2']) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(id: Value(n), title: Value('Chapter $n')),
          );
      await addNoteToProject(db, projectId: id, noteId: n);
    }
    var i = 0;
    for (final (note, resolved) in [
      ('n1', false),
      ('n1', false),
      ('n1', true),
    ]) {
      await db
          .into(db.noteComments)
          .insert(
            NoteCommentsCompanion.insert(
              id: Value('c${i++}'),
              noteId: note,
              quote: const Value('x'),
              body: const Value('fix'),
              resolved: Value(resolved),
            ),
          );
    }
    return id;
  }

  testWidgets('a chapter with open comments says so; others stay plain', (
    tester,
  ) async {
    final id = await seed();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          coverRendererProvider.overrideWithValue((_) async => null),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ProjectScreen(projectId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 open comments'), findsOneWidget);
    expect(find.textContaining('comment'), findsOneWidget);

    // Tapping it opens the note with the comments panel.
    await tester.tap(find.text('2 open comments'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('comments-panel')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
