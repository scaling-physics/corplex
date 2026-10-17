import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/home/adaptive.dart' show selectedPaperProvider;
import 'package:corplex/features/library/all_highlights_screen.dart';
import 'package:corplex/features/library/pdf_search.dart';
import 'package:corplex/theme/mac_list_row.dart';
import 'package:corplex/features/library/library_screen.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/library/paper_detail_screen.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';
import 'package:corplex/features/library/split_fraction.dart';
import 'package:corplex/features/library/split_reader.dart';
import 'package:corplex/features/library/viewer_keys.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/theme/app_theme.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

/// Two "alpha" matches on page 1.
class _FakeSource implements PageTextSource {
  @override
  int get pageCount => 1;
  @override
  Future<List<Rect>> find(int page, String query) async => query == 'alpha'
      ? const [
          Rect.fromLTWH(0.1, 0.1, 0.2, 0.02),
          Rect.fromLTWH(0.1, 0.3, 0.2, 0.02),
        ]
      : const [];
}

void main() {
  late AppDatabase db;

  setUpAll(loadMacFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani, Ashish; Shazeer, Noam'),
            year: const Value(2017),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p2'),
            title: 'A Mathematical Framework for Transformer Circuits',
            authors: const Value('Elhage, Nelson'),
            year: const Value(2021),
          ),
        );
    await db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            paperId: 'p1',
            pageNumber: 3,
            quote: 'The Transformer allows for significantly more parallelization.',
            rectsJson: '[[0.1,0.1,0.5,0.02]]',
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Widget app(Widget home, {ThemeMode mode = ThemeMode.light}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      coverRendererProvider.overrideWithValue((_) async => null),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      builder: (context, child) => MacWindowFrame(child: child!),
      home: home,
    ),
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('right-click a paper: Move to trash, then Undo', (tester) async {
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await tester.pumpWidget(app(const Scaffold(body: LibraryScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Attention Is All You Need'), findsOneWidget);

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(tester.getCenter(find.text('Attention Is All You Need')));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Add to project…'), findsOneWidget);
    expect(find.text('Copy citation'), findsOneWidget);
    expect(find.text('Open PDF'), findsNothing, reason: 'no local PDF');
    await macScreenshot(tester, 'library-context-menu');

    await tester.tap(find.text('Move to trash'));
    await tester.pumpAndSettle();
    expect(find.text('Attention Is All You Need'), findsNothing);
    expect(find.textContaining('moved to trash'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Attention Is All You Need'), findsOneWidget);
    await close(tester);
  }, variant: macOnly);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final name in ['laptop13', 'display27']) {
      testWidgets('library list ${mode.name} $name', (tester) async {
        useMacWindow(tester, macWindowSizes[name]!);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(width: 380, child: const LibraryScreen()),
              ),
            ),
            mode: mode,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await macScreenshot(tester, 'library-${mode.name}-$name');
        await close(tester);
      }, variant: macOnly);
    }
  }

  for (final MapEntry(key: name, value: size) in macWindowSizes.entries) {
    for (final embedded in [true, false]) {
      testWidgets('paper screen $name embedded=$embedded', (tester) async {
        useMacWindow(tester, size);
        await tester.pumpWidget(
          app(PaperDetailScreen(paperId: 'p1', embedded: embedded)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (embedded) await macScreenshot(tester, 'paper-$name');
        await close(tester);
      }, variant: macOnly);
    }
  }

  testWidgets('paper screen dark at display27', (tester) async {
    useMacWindow(tester, macWindowSizes['display27']!);
    await tester.pumpWidget(
      app(
        const PaperDetailScreen(paperId: 'p1', embedded: true),
        mode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await macScreenshot(tester, 'paper-dark-display27');
    await close(tester);
  }, variant: macOnly);

  for (final name in ['laptop13', 'display27']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('viewer chrome ${mode.name} $name', (tester) async {
        useMacWindow(tester, macWindowSizes[name]!);
        await tester.pumpWidget(
          app(
            PdfViewerScreen(
              paperId: 'p1',
              pdfPath: '/none.pdf',
              viewerBuilder: (context, controller, params) =>
                  Center(child: Container(width: 600, color: Colors.white)),
            ),
            mode: mode,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await macScreenshot(tester, 'viewer-${mode.name}-$name');
        await close(tester);
      }, variant: macOnly);
    }
  }

  group('viewer keys', () {
    testWidgets('map to the right actions; typing is not paging', (
      tester,
    ) async {
      final log = <String>[];
      var typing = false;
      final actions = ViewerKeyActions(
        zoomIn: () => log.add('in'),
        zoomOut: () => log.add('out'),
        fit: () => log.add('fit'),
        nextPage: () => log.add('next'),
        previousPage: () => log.add('prev'),
        firstPage: () => log.add('first'),
        lastPage: () => log.add('last'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: viewerKeyBindings(actions, enabled: () => !typing),
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      );
      Future<void> press(LogicalKeyboardKey key, {bool meta = false}) async {
        if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }

      await press(LogicalKeyboardKey.equal, meta: true);
      await press(LogicalKeyboardKey.minus, meta: true);
      await press(LogicalKeyboardKey.digit0, meta: true);
      await press(LogicalKeyboardKey.pageDown);
      await press(LogicalKeyboardKey.space);
      await press(LogicalKeyboardKey.pageUp);
      await press(LogicalKeyboardKey.home);
      await press(LogicalKeyboardKey.end);
      expect(log, [
        'in',
        'out',
        'fit',
        'next',
        'next',
        'prev',
        'first',
        'last',
      ]);
      log.clear();
      typing = true;
      await press(LogicalKeyboardKey.space);
      expect(log, isEmpty);
    }, variant: macOnly);
  });

  group('split reader', () {
    test('clamps: PDF keeps 45%, note keeps 320 pt', () {
      expect(clampSplitFraction(0.1, 1280), minReaderFraction);
      expect(clampSplitFraction(0.99, 1280), closeTo(1 - 320 / 1280, 1e-9));
      expect(clampSplitFraction(0.99, 2560), closeTo(1 - 320 / 2560, 1e-9));
      expect(clampSplitFraction(0.55, 1280), 0.55);
    });

    testWidgets('dragging the divider resizes, clamps and persists', (
      tester,
    ) async {
      useMacWindow(tester, macWindowSizes['laptop13']!);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => ResizableSplit(
                total: 1280,
                fraction: ref.watch(splitFractionProvider),
                onChanged: ref.read(splitFractionProvider.notifier).save,
                reader: const ColoredBox(color: Colors.white, key: Key('r')),
                note: const ColoredBox(color: Colors.green, key: Key('n')),
              ),
            ),
          ),
        ),
      );
      double readerWidth() => tester.getSize(find.byKey(const Key('r'))).width;
      expect(readerWidth(), closeTo(1280 * defaultSplitFraction, 1));

      final divider = find.byKey(const ValueKey('split-divider'));
      await tester.drag(divider, const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(readerWidth(), closeTo(1280 * 0.55 + 100, 25));

      await tester.drag(divider, const Offset(2000, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('n'))).width,
        greaterThanOrEqualTo(minNoteWidth - ResizableSplit.grip),
      );

      await tester.drag(divider, const Offset(-3000, 0));
      await tester.pumpAndSettle();
      expect(readerWidth(), closeTo(1280 * minReaderFraction, 1));

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(splitFractionKey),
        closeTo(minReaderFraction, 1e-6),
      );
    }, variant: macOnly);

    test('a saved fraction is loaded', () async {
      SharedPreferences.setMockInitialValues({splitFractionKey: 0.6});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(splitFractionProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(splitFractionProvider), 0.6);
    });
  });

  group('keyboard', () {
    testWidgets('Library rows: Up/Down move the selection, Return opens', (
      tester,
    ) async {
      useMacWindow(tester, macWindowSizes['laptop13']!);
      await tester.pumpWidget(app(const Scaffold(body: LibraryScreen())));
      await tester.pumpAndSettle();
      expect(find.byType(MacListRow), findsNWidgets(2));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryScreen)),
      );
      // Newest first or by title: read the order the rows show.
      final first = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byType(MacListRow).first,
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!;
      await tester.tap(find.text(first));
      await tester.pumpAndSettle();
      final id1 = container.read(selectedPaperProvider);
      expect(id1, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final id2 = container.read(selectedPaperProvider);
      expect(id2, isNot(id1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(container.read(selectedPaperProvider), id1);
      await close(tester);
    }, variant: macOnly);

    testWidgets('menu commands reach the viewer: Find, next match', (
      tester,
    ) async {
      useMacWindow(tester, macWindowSizes['laptop13']!);
      await tester.pumpWidget(
        app(
          PdfViewerScreen(
            paperId: 'p1',
            pdfPath: '/none.pdf',
            viewerBuilder: (context, controller, params) =>
                const SizedBox.expand(),
            searchSourceBuilder: (_) => _FakeSource(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('find-field')), findsNothing);
      expect(dispatchMenuCommand(MenuCommand.find), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('find-field')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('find-field')), 'alpha');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      String count() =>
          tester.widget<Text>(find.byKey(const ValueKey('find-count'))).data!;
      expect(count(), '1 of 2');
      expect(dispatchMenuCommand(MenuCommand.findNext), isTrue);
      await tester.pump();
      expect(count(), '2 of 2');
      expect(dispatchMenuCommand(MenuCommand.findPrevious), isTrue);
      await tester.pump();
      expect(count(), '1 of 2');
      // Zoom before a document loads is a harmless no-op.
      expect(dispatchMenuCommand(MenuCommand.zoomIn), isTrue);
      expect(dispatchMenuCommand(MenuCommand.actualSize), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(count(), '2 of 2');
      await close(tester);
    }, variant: macOnly);
  });

  testWidgets('Return opens the viewer for a paper with a PDF', (tester) async {
    await tester.runAsync(
      () => (db.update(db.papers)..where((p) => p.id.equals('p2'))).write(
        const PapersCompanion(pdfPath: Value('/none.pdf')),
      ),
    );
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await tester.pumpWidget(app(const Scaffold(body: LibraryScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MacListRow).last);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PdfViewerScreen), findsOneWidget);
    await close(tester);
  }, variant: macOnly);

  testWidgets('all highlights fills the window', (tester) async {
    useMacWindow(tester, macWindowSizes['display27']!);
    await tester.pumpWidget(app(const AllHighlightsScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await macScreenshot(tester, 'highlights-display27');
    await close(tester);
  }, variant: macOnly);

  group('paper layout', () {
    testWidgets('two columns on a wide pane', (tester) async {
      useMacWindow(tester, macWindowSizes['display27']!);
      await tester.pumpWidget(
        app(const PaperDetailScreen(paperId: 'p1', embedded: true)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final details = tester.getTopLeft(find.text('Details'));
      final highlights = tester.getTopLeft(find.text('Highlights'));
      expect(highlights.dx, greaterThan(details.dx + 300));
      // Fills the pane up to the Mac measure cap, then centres it.
      expect(details.dx, macPanePadding(2560));
      await close(tester);
    }, variant: macOnly);

    testWidgets('one full-width column on a narrow pane', (tester) async {
      useMacWindow(tester, macWindowSizes['laptop13']!);
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 760,
              child: const PaperDetailScreen(paperId: 'p1', embedded: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Highlights')).dx,
        tester.getTopLeft(find.text('Details')).dx,
      );
      await close(tester);
    }, variant: macOnly);
  });
}
