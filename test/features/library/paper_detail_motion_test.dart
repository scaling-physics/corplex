import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/library/paper_detail_screen.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';

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

  Future<void> insert({String? pdfPath}) => db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          id: const Value('p1'),
          title: 'Attention Is All You Need',
          pdfPath: Value(pdfPath),
        ),
      );

  Future<Paper> paper() =>
      (db.select(db.papers)..where((p) => p.id.equals('p1'))).getSingle();

  Future<void> show(WidgetTester tester, {bool reduced = false}) async {
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
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: const PaperDetailScreen(paperId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder compactTitle() => find.descendant(
    of: find.byType(SliverAppBar),
    matching: find.text('Attention Is All You Need'),
  );

  testWidgets('compact title appears in the app bar after scrolling', (
    tester,
  ) async {
    await insert();
    await show(tester);
    expect(compactTitle(), findsNothing);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -500),
      1000,
    );
    await tester.pumpAndSettle();
    expect(compactTitle(), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 1500),
      3000,
    );
    await tester.pumpAndSettle();
    expect(compactTitle(), findsNothing);
    await close(tester);
  });

  testWidgets('reduced motion shows the compact title without a slide', (
    tester,
  ) async {
    await insert();
    await show(tester, reduced: true);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -500),
      1000,
    );
    await tester.pumpAndSettle();
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: compactTitle(), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
    await close(tester);
  });

  testWidgets('editing the title still autosaves', (tester) async {
    await insert();
    await show(tester);
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect((await paper()).title, 'Renamed');
    await close(tester);
  });

  testWidgets('stars update the DB, animate in and settle', (tester) async {
    await insert();
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('star-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    // Mid-flight: the third star (staggered last) is partly scaled.
    await tester.pumpAndSettle();
    expect((await paper()).rating, 3);

    await tester.tap(find.byKey(const ValueKey('star-3')));
    await tester.pumpAndSettle();
    expect((await paper()).rating, isNull);
    await close(tester);
  });

  testWidgets('reduced motion fills stars immediately', (tester) async {
    await insert();
    await show(tester, reduced: true);
    await tester.tap(find.byKey(const ValueKey('star-2')));
    await tester.pump();
    await tester.pump();
    final scales = tester.widgetList<Transform>(
      find.descendant(
        of: find.byKey(const ValueKey('star-2')),
        matching: find.byType(Transform),
      ),
    );
    expect(scales.any((t) => t.transform.getMaxScaleOnAxis() == 1), isTrue);
    expect((await paper()).rating, 2);
    await close(tester);
  });

  testWidgets('status chips select, move and clear', (tester) async {
    await insert();
    await show(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Reading'));
    await tester.pumpAndSettle();
    expect((await paper()).readingStatus, ReadingStatus.reading);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
    await tester.pumpAndSettle();
    expect((await paper()).readingStatus, ReadingStatus.done);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
    await tester.pumpAndSettle();
    expect((await paper()).readingStatus, isNull);
    await close(tester);
  });

  testWidgets('tapping the cover opens the viewer; no PDF, no action', (
    tester,
  ) async {
    await insert();
    await show(tester);
    await tester.tap(find.byType(PaperCover));
    await tester.pumpAndSettle();
    expect(find.byType(PdfViewerScreen), findsNothing);
    await close(tester);
  });

  testWidgets('cover with a PDF opens the viewer', (tester) async {
    await insert(pdfPath: '/nonexistent/paper.pdf');
    await show(tester);
    await tester.tap(find.byType(PaperCover));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PdfViewerScreen), findsOneWidget);
    await close(tester);
  });
}
