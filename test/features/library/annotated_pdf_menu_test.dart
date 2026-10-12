import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/annotated_pdf_export.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/library/paper_detail_screen.dart';

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

  Future<void> insertPaper({String? pdfPath}) => db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          id: const Value('p1'),
          title: 'A/B: Paper?',
          pdfPath: Value(pdfPath),
        ),
      );

  Future<void> addHighlight() => db
      .into(db.highlights)
      .insert(
        HighlightsCompanion.insert(
          paperId: 'p1',
          pageNumber: 1,
          quote: 'q',
          rectsJson: '[[0.1,0.1,0.5,0.2]]',
        ),
      );

  Future<void> openMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          coverRendererProvider.overrideWithValue((_) async => null),
        ],
        child: const MaterialApp(home: PaperDetailScreen(paperId: 'p1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('shown with a local PDF and a highlight', (tester) async {
    await insertPaper(pdfPath: '/tmp/x.pdf');
    await addHighlight();
    await openMenu(tester);
    expect(find.text('Export with highlights'), findsOneWidget);
    await close(tester);
  });

  testWidgets('hidden when there is nothing to export', (tester) async {
    await insertPaper(pdfPath: '/tmp/x.pdf');
    await openMenu(tester);
    expect(find.text('Move to trash'), findsOneWidget);
    expect(find.text('Export with highlights'), findsNothing);
    await close(tester);
  });

  testWidgets('hidden without a local PDF', (tester) async {
    await insertPaper();
    await addHighlight();
    await openMenu(tester);
    expect(find.text('Export with highlights'), findsNothing);
    await close(tester);
  });

  test('file name is "<title> (annotated).pdf" and safe', () {
    expect(annotatedFileName('A/B: Paper?'), 'A_B_ Paper_ (annotated).pdf');
    expect(annotatedFileName('  '), 'Paper (annotated).pdf');
  });
}
