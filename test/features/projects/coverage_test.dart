import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/projects/coverage.dart';
import 'package:corplex/features/projects/projects_providers.dart';

String body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

Paper paper(
  String id,
  String key, {
  ReadingStatus? status,
  String title = '',
}) => Paper(
  id: id,
  title: title.isEmpty ? 'Title $id' : title,
  authors: 'Smith, Ann',
  year: 2020,
  citekey: key,
  readingStatus: status,
  createdAt: DateTime(2020),
  updatedAt: DateTime(2020),
);

void main() {
  group('computeCoverage', () {
    final papers = [
      paper('a', 'a2020'),
      paper('b', 'b2020'),
      paper('c', 'c2020', status: ReadingStatus.done),
      paper('d', 'd2020'),
      paper('e', 'e2020', status: ReadingStatus.toRead),
    ];

    test('counts occurrences, multi-key groups and unknown keys', () {
      final cov = computeCoverage(
        chapters: [
          CoverageNote(
            id: 'n1',
            title: 'Intro',
            content: body('See [@a2020] and [@a2020; @b2020], also [@zzz].'),
          ),
          CoverageNote(id: 'n2', title: 'Method', content: body('[@b2020]')),
        ],
        papers: papers,
        projectPaperIds: {'a', 'b'},
      );
      expect(cov.chapters.length, 2);
      expect(
        [for (final c in cov.chapters[0].cited) (c.paper.id, c.count)],
        [('a', 2), ('b', 1)],
      );
      expect(
        [for (final c in cov.chapters[1].cited) (c.paper.id, c.count)],
        [('b', 1)],
      );
      expect(cov.unknownKeys, {'zzz'});
      final b = cov.cited.firstWhere((c) => c.paper.id == 'b');
      expect(
        [for (final c in b.chapters) (c.index, c.count)],
        [(0, 1), (1, 1)],
      );
      expect(cov.citedOutsideProject, isEmpty);
      expect(cov.readNotCited, isEmpty);
    });

    test(
      'read but not cited: ranked by highlights, status shown, linked too',
      () {
        final cov = computeCoverage(
          chapters: [
            CoverageNote(id: 'n1', title: 'I', content: body('[@a2020]')),
          ],
          papers: papers,
          projectPaperIds: {'a', 'b', 'c', 'e'},
          linkedPaperIds: {'d'},
          highlightCounts: {'b': 2, 'c': 5, 'd': 1, 'e': 0},
        );
        // a is cited; e is untouched (to-read, no highlights).
        expect(
          [for (final u in cov.readNotCited) (u.paper.id, u.highlights)],
          [('c', 5), ('b', 2), ('d', 1)],
        );
      },
    );

    test('a finished paper with no highlights still counts as read', () {
      final cov = computeCoverage(
        chapters: const [],
        papers: papers,
        projectPaperIds: {'c'},
      );
      expect(cov.readNotCited.single.paper.id, 'c');
    });

    test('linked paper without highlights is not read', () {
      final cov = computeCoverage(
        chapters: const [],
        papers: papers,
        projectPaperIds: {},
        linkedPaperIds: {'d'},
      );
      expect(cov.isEmpty, isTrue);
    });

    test('cited but not in the project', () {
      final cov = computeCoverage(
        chapters: [
          CoverageNote(id: 'n1', title: 'I', content: body('[@d2020]')),
        ],
        papers: papers,
        projectPaperIds: {'a'},
      );
      expect(cov.citedOutsideProject.map((p) => p.id), ['d']);
      expect(cov.isEmpty, isFalse);
    });
  });

  group('ChapterCoverageSection', () {
    late AppDatabase db;
    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
    });
    tearDown(() => db.close());

    Future<void> pumpSection(
      WidgetTester tester,
      String project,
      List<String> ids,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChapterCoverageSection(
                  projectId: project,
                  orderedNoteIds: ids,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> addPaper(
      String id,
      String key, {
      ReadingStatus? status,
      String? project,
    }) async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: Value(id),
              title: 'Paper $id',
              citekey: Value(key),
              readingStatus: Value(status),
            ),
          );
      if (project != null) {
        await addPaperToProject(db, projectId: project, paperId: id);
      }
    }

    testWidgets('hidden with no papers and no citations', (tester) async {
      final p = await findOrCreateProject(db, 'T');
      await pumpSection(tester, p, const []);
      expect(find.text('Citations'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('collapsed rows expand and list the uncited papers', (
      tester,
    ) async {
      final p = await findOrCreateProject(db, 'T');
      await addPaper('a', 'a2020', project: p);
      await addPaper('b', 'b2020', status: ReadingStatus.done, project: p);
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Intro'),
              content: Value(body('As shown [@a2020].')),
            ),
          );
      await pumpSection(tester, p, ['n1']);
      expect(find.text('Citations'), findsOneWidget);
      expect(find.text('Cited in chapters (1)'), findsOneWidget);
      expect(find.text('Read but not cited (1)'), findsOneWidget);
      // Collapsed: no paper rows yet.
      expect(find.byKey(const ValueKey('uncited-b')), findsNothing);
      await tester.tap(find.text('Read but not cited (1)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uncited-b')), findsOneWidget);
      expect(find.textContaining('Read'), findsWidgets);
      await tester.tap(find.text('Cited in chapters (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Ch. 1 · 1×'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
