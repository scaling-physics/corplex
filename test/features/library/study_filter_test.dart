import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/library/library_screen.dart';
import 'package:corplex/features/library/papers_providers.dart';
import 'package:corplex/features/library/study_details.dart';
import 'package:corplex/features/library/study_filter.dart';
import 'package:corplex/features/projects/projects_providers.dart';

Future<void> _paper(
  AppDatabase db,
  String id,
  String title, {
  String? species,
  String? regions,
  int? n,
  String? paradigm,
  ReadingStatus? status,
}) => db
    .into(db.papers)
    .insert(
      PapersCompanion.insert(
        id: Value(id),
        title: title,
        species: Value(species),
        brainRegions: Value(regions),
        sampleSize: Value(n),
        paradigm: Value(paradigm),
        readingStatus: Value(status),
      ),
    );

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

  Future<void> seed() async {
    await _paper(
      db,
      'a',
      'Place cells',
      species: 'rat',
      regions: 'CA1; CA3',
      n: 6,
    );
    await _paper(
      db,
      'b',
      'Grid cells',
      species: 'Mouse',
      regions: 'entorhinal cortex',
      n: 20,
      status: ReadingStatus.done,
    );
    await _paper(
      db,
      'c',
      'Memory in humans',
      species: 'human',
      regions: 'CA1',
      n: 40,
      paradigm: 'sleep',
    );
    await _paper(db, 'd', 'Untagged');
    await db
        .into(db.projects)
        .insert(ProjectsCompanion.insert(id: const Value('pr'), name: 'T'));
    await db
        .into(db.projectPapers)
        .insert(ProjectPapersCompanion.insert(projectId: 'pr', paperId: 'a'));
    await db
        .into(db.projectPapers)
        .insert(ProjectPapersCompanion.insert(projectId: 'pr', paperId: 'c'));
  }

  Future<Set<String>> titles(ProviderContainer c) async {
    c.listen(filteredPapersProvider, (_, _) {});
    c.listen(projectPaperIdsProvider('pr'), (_, _) {});
    await c.read(papersListProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return {for (final p in c.read(filteredPapersProvider).value!) p.title};
  }

  test(
    'OR within a field, AND across, min n, combined with other filters',
    () async {
      await seed();
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(c.dispose);
      c.listen(studyFilterProvider, (_, _) {});
      c.listen(papersListProvider, (_, _) {});
      final n = c.read(studyFilterProvider.notifier);

      expect(await titles(c), hasLength(4));

      n.state = n.state
          .toggled(StudyField.species, 'RAT')
          .toggled(StudyField.species, 'mouse');
      expect(await titles(c), {
        'Place cells',
        'Grid cells',
      }); // OR, case-insensitive

      n.state = n.state.toggled(StudyField.brainRegions, 'CA1');
      expect(await titles(c), {'Place cells'}); // AND

      n.state = const StudyFilter().toggled(StudyField.brainRegions, 'CA1');
      expect(await titles(c), {'Place cells', 'Memory in humans'});
      n.state = n.state.withMinSampleSize(10);
      expect(await titles(c), {'Memory in humans'});
      expect(n.state.count, 2);

      n.state = const StudyFilter().withMinSampleSize(10);
      expect(await titles(c), {'Grid cells', 'Memory in humans'});

      // With search, status and project.
      c.read(librarySearchProvider.notifier).state = 'cells';
      expect(await titles(c), {'Grid cells'});
      c.read(librarySearchProvider.notifier).state = '';
      c.read(libraryStatusFilterProvider.notifier).state = ReadingStatus.done;
      expect(await titles(c), {'Grid cells'});
      c.read(libraryStatusFilterProvider.notifier).state = null;
      c.read(libraryProjectFilterProvider.notifier).state = 'pr';
      expect(await titles(c), {'Memory in humans'});
    },
  );

  testWidgets(
    'the Study chip is hidden until a paper has study details; the sheet filters',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _paper(db, 'd', 'Untagged');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: Scaffold(body: LibraryScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StudyFilterChip), findsNothing);

      await (db.update(db.papers)..where((p) => p.id.equals('d'))).write(
        const PapersCompanion(species: Value('rat'), sampleSize: Value(5)),
      );
      await _paper(db, 'e', 'Other', species: 'mouse', n: 30);
      await tester.pumpAndSettle();
      expect(find.text('Study'), findsOneWidget);

      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'mouse'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Study · 1'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Untagged'), findsNothing);

      await tester.tap(find.byTooltip('Clear study filter')); // clear
      await tester.pumpAndSettle();
      expect(find.text('Study'), findsOneWidget);
      expect(find.text('Untagged'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('the Study chip survives 2x text scale', (tester) async {
    await seed();
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: LibraryScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
