import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/projects/project_menu.dart';
import 'package:corplex/features/projects/project_page.dart';
import 'package:corplex/features/projects/projects_providers.dart';

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

  Future<String> seed({bool papers = true, bool notes = true}) async {
    final id = await findOrCreateProject(db, 'Thesis');
    if (papers) {
      for (final (pid, title, status) in [
        ('p1', 'Attention', ReadingStatus.done),
        ('p2', 'BERT', ReadingStatus.reading),
      ]) {
        await db
            .into(db.papers)
            .insert(
              PapersCompanion.insert(
                id: Value(pid),
                title: title,
                readingStatus: Value(status),
              ),
            );
        await addPaperToProject(db, projectId: id, paperId: pid);
      }
    }
    if (notes) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Lecture'),
            ),
          );
      await addNoteToProject(db, projectId: id, noteId: 'n1');
    }
    return id;
  }

  Widget app(Widget home) => ProviderScope(
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
      home: home,
    ),
  );

  testWidgets('shows summary, progress and both sections', (tester) async {
    final id = await seed();
    await tester.pumpWidget(app(ProjectScreen(projectId: id)));
    await tester.pumpAndSettle();

    expect(find.text('Thesis'), findsOneWidget);
    expect(find.text('2 papers · 1 note'), findsOneWidget);
    expect(find.text('1 of 2 read'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const ValueKey('project-progress')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(bar.value, 0.5);
    expect(find.text('Papers'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Attention'), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Synthesis matrix'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('hides sections and actions that would be empty', (tester) async {
    final id = await seed(papers: false);
    await tester.pumpWidget(app(ProjectScreen(projectId: id)));
    await tester.pumpAndSettle();

    expect(find.text('0 papers · 1 note'), findsOneWidget);
    expect(find.text('Papers'), findsNothing);
    expect(find.byKey(const ValueKey('project-progress')), findsNothing);
    expect(find.text('Synthesis matrix'), findsNothing);
    expect(find.text('Export project'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a new project says it is empty', (tester) async {
    final id = await seed(papers: false, notes: false);
    await tester.pumpWidget(app(ProjectScreen(projectId: id)));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Papers'), findsNothing);
    expect(find.text('Notes'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('opens from the project menu, and a note opens from it', (
    tester,
  ) async {
    final id = await seed();
    final project = await (db.select(
      db.projects,
    )..where((p) => p.id.equals(id))).getSingle();
    await tester.pumpWidget(
      app(
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => showProjectMenu(context, ref, project),
              child: const Text('menu'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    expect(find.text('Open project'), findsOneWidget);
    await tester.tap(find.text('Open project'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectScreen), findsOneWidget);

    await tester.tap(find.text('Lecture'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
