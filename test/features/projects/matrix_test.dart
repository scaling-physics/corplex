import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/projects/matrix.dart';
import 'package:corplex/features/projects/matrix_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(id: const Value('pr'), name: 'Thesis'),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention',
            authors: const Value('Vaswani, Ashish'),
            year: const Value(2017),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p2'),
            title: 'BERT',
            authors: const Value('Devlin, J; Chang, M; Lee, K'),
            year: const Value(2019),
          ),
        );
    await db
        .into(db.projectPapers)
        .insert(ProjectPapersCompanion.insert(projectId: 'pr', paperId: 'p1'));
    await db
        .into(db.projectPapers)
        .insert(ProjectPapersCompanion.insert(projectId: 'pr', paperId: 'p2'));
    await db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: const Value('h1'),
            paperId: 'p1',
            pageNumber: 3,
            quote: 'self-attention',
            rectsJson: '[]',
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  test(
    'columns keep their order; cells set, clear, and cascade with their column',
    () async {
      final a = await addMatrixColumn(db, 'pr', 'Method');
      final b = await addMatrixColumn(db, 'pr', ' Findings ');
      final cols = await (db.select(
        db.matrixColumns,
      )..orderBy([(c) => OrderingTerm.asc(c.position)])).get();
      expect(cols.map((c) => c.name), ['Method', 'Findings']);

      await setMatrixCell(db, a, 'p1', 'Transformer');
      await setMatrixCell(
        db,
        a,
        'p1',
        'Transformer, encoder-decoder',
      ); // overwrite
      await setMatrixCell(db, b, 'p2', 'SOTA');
      expect(await db.select(db.matrixCells).get(), hasLength(2));

      await setMatrixCell(db, b, 'p2', '   '); // blank clears
      expect(await db.select(db.matrixCells).get(), hasLength(1));

      await deleteMatrixColumn(db, a);
      expect(await db.select(db.matrixCells).get(), isEmpty);
    },
  );

  test('cells, columns and papers all sync', () async {
    final a = await addMatrixColumn(db, 'pr', 'Method');
    await setMatrixCell(db, a, 'p1', 'x');
    final dirty = await db
        .customSelect(
          "SELECT table_name FROM sync_dirty WHERE table_name LIKE 'matrix%'",
        )
        .get();
    expect(dirty.map((r) => r.read<String>('table_name')).toSet(), {
      'matrix_columns',
      'matrix_cells',
    });
  });

  test(
    'the Markdown table has a row per paper and a column per theme',
    () async {
      final a = await addMatrixColumn(db, 'pr', 'Method');
      final b = await addMatrixColumn(db, 'pr', 'Findings');
      await setMatrixCell(db, a, 'p1', 'A | B'); // pipes must be escaped
      final cols = await db.select(db.matrixColumns).get()
        ..sort((x, y) => x.position.compareTo(y.position));
      final papers = await db.select(db.papers).get()
        ..sort((x, y) => x.title.compareTo(y.title));
      final md = matrixToMarkdown(cols, papers, {
        '$a|p1': r'A | B',
        '$b|p2': 'SOTA',
      });
      expect(md.trim().split('\n'), [
        '| Paper | Method | Findings |',
        '| --- | --- | --- |',
        r'| Vaswani 2017 | A \| B |  |',
        '| Devlin et al. 2019 |  | SOTA |',
      ]);
    },
  );

  testWidgets(
    'empty project matrix offers the usual themes, and a cell can be filled from a highlight',
    (tester) async {
      final project = await (db.select(
        db.projects,
      )..where((p) => p.id.equals('pr'))).getSingle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(home: MatrixScreen(project: project)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Compare papers side by side'), findsOneWidget);

      await tester.tap(find.text('Add method, sample, findings'));
      await tester.pumpAndSettle();
      expect(find.text('Method'), findsOneWidget);
      expect(find.text('Vaswani 2017'), findsOneWidget);

      // Open the first cell of the first paper's row and pull in a highlight.
      await tester.tapAt(
        tester.getCenter(find.text('Vaswani 2017')) + const Offset(200, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('From your highlights'), findsOneWidget);
      await tester.tap(find.text('self-attention'));
      await tester.pump();
      await tester.tapAt(const Offset(5, 5)); // dismiss the sheet
      await tester.pumpAndSettle();

      final cell = await db.select(db.matrixCells).getSingle();
      expect(cell.paperId, 'p1');
      expect(cell.text_, '“self-attention” (p. 3)');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
