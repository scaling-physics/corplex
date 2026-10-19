import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/comments/comments_data.dart';
import 'package:corplex/features/comments/comments_panel.dart';
import 'package:corplex/features/graph/graph_screen.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/notes/figure_embed.dart';
import 'package:corplex/features/notes/figure_markers.dart' show FigureKind;
import 'package:corplex/features/notes/note_stats.dart';
import 'package:corplex/features/notes/note_versions_screen.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:corplex/features/projects/project_page.dart';
import 'package:corplex/features/projects/projects_providers.dart';
import 'package:corplex/l10n/l10n.dart';

import '../support/fake_audio_engine.dart';
import '../support/l10n_app.dart';

void main() {
  late AppDatabase db;
  final de = lookupAppLocalizations(const Locale('de'));

  setUpAll(() => initializeDateFormatting('de'));
  setUp(() {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      coverRendererProvider.overrideWithValue((_) async => null),
    ],
    child: localizedApp(home),
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  test('labels, plurals and dates follow the language', () {
    expect(
      chapterStatusLabel(ChapterStatus.withSupervisor, de),
      'Bei Betreuer:in',
    );
    expect(chapterStatusLabel(ChapterStatus.finished), 'Final');
    expect(de.projectsChaptersFinal(1, 3), '1 von 3 Kapiteln final');
    expect(de.projectsWordsOfTarget(12400, 40000), '12.400 / 40.000 Wörter');
    expect(
      dueLabel(DateTime(2027, 3, 14), DateTime(2026, 10, 12), de),
      'Fällig am 14. März 2027 · in 153 Tagen',
    );
    expect(
      dueLabel(DateTime(2026, 10, 9), DateTime(2026, 10, 12), de),
      'Fällig am 9. Oktober · vor 3 Tagen',
    );
    expect(openCommentsLabel(2, de), '2 offene Kommentare');
    expect(openCommentsLabel(1, de), '1 offener Kommentar');
    expect(figureDisplayName(de, FigureKind.figure, '3.2'), 'Abbildung 3.2');
    expect(figureDisplayName(de, FigureKind.table, null), 'Tabelle ??');
    final stats = NoteStats(
      words: 500,
      characters: 3000,
      paragraphs: 4,
      citations: 0,
    );
    expect(readingTimeLabel(stats, de), '3 Min.');
  });

  testWidgets('project page in German', (tester) async {
    final id = await findOrCreateProject(db, 'Thesis');
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention',
            readingStatus: const Value(ReadingStatus.done),
          ),
        );
    await addPaperToProject(db, projectId: id, paperId: 'p1');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Einleitung'),
          ),
        );
    await addNoteToProject(db, projectId: id, noteId: 'n1');

    await tester.pumpWidget(app(ProjectScreen(projectId: id)));
    await tester.pumpAndSettle();
    expect(find.text('1 Paper · 1 Notiz'), findsOneWidget);
    expect(find.text('1 von 1 gelesen'), findsOneWidget);
    expect(find.text('Synthesematrix'), findsOneWidget);
    expect(find.text('Kapitel'), findsOneWidget);
    expect(find.text('Kapitel hinzufügen'), findsOneWidget);
    expect(find.text('Abgabedatum festlegen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets('map and versions in German', (tester) async {
    await tester.pumpWidget(app(const GraphScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Karte'), findsOneWidget);
    expect(find.text('Noch nichts zum Darstellen'), findsOneWidget);
    await dispose(tester);

    await db.into(db.notes).insert(NotesCompanion.insert(id: const Value('n')));
    await tester.pumpWidget(
      app(NoteVersionsScreen(noteId: 'n', flush: () async {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('Versionen'), findsOneWidget);
    expect(find.text('Noch keine Versionen'), findsOneWidget);
    expect(find.text('Jetzt Version sichern'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets('comments panel in German', (tester) async {
    await db.into(db.notes).insert(NotesCompanion.insert(id: const Value('n')));
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CommentsPanel(
            noteId: 'n',
            locate: (_) => null,
            onPick: (_, _) {},
            onAdd: () {},
            onClose: () {},
            hasSelection: ValueNotifier(false),
            onEdit: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kommentare'), findsOneWidget);
    expect(
      find.text('Eine Stelle auswählen, dann „Kommentar hinzufügen“ wählen.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });
}
