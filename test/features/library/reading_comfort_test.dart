import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/all_highlights_screen.dart';
import 'package:corplex/features/library/papers_providers.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';
import 'package:corplex/features/settings/appearance_settings.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';

class _NoShares implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> initial() async => const [];

  @override
  Stream<List<SharedMediaFile>> get stream => const Stream.empty();

  @override
  Future<void> reset() async {}
}

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

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
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('b'), title: 'Beta paper'),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('a'),
            title: 'Alpha paper',
            pdfPath: const Value('/a.pdf'),
          ),
        );
    Future<void> h(
      String id,
      String paper,
      int page,
      String quote, {
      String? comment,
    }) => db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: Value(id),
            paperId: paper,
            pageNumber: page,
            quote: quote,
            rectsJson: '[]',
            comment: Value(comment),
          ),
        );
    await h('1', 'b', 2, 'gradient descent');
    await h('2', 'a', 9, 'late passage');
    await h('3', 'a', 1, 'early passage', comment: 'remember this');
  }

  group('reading themes', () {
    test('paper shows the page as printed; sepia and night filter it', () {
      expect(ReadingTheme.paper.filter, isNull);
      expect(ReadingTheme.sepia.filter, isNotNull);
      expect(ReadingTheme.night.filter, isNotNull);
    });

    test(
      'settings persist, and unknown stored values fall back to defaults',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fresh = await AppearanceSettings.load();
        expect(
          (fresh.themeMode, fresh.reading),
          (ThemeMode.system, ReadingTheme.paper),
        );

        await fresh.setThemeMode(ThemeMode.dark);
        await fresh.setReading(ReadingTheme.night);
        final again = await AppearanceSettings.load();
        expect(
          (again.themeMode, again.reading),
          (ThemeMode.dark, ReadingTheme.night),
        );

        SharedPreferences.setMockInitialValues({
          'appearance.themeMode': 'neon',
          'appearance.reading': 'sparkle',
        });
        final odd = await AppearanceSettings.load();
        expect(
          (odd.themeMode, odd.reading),
          (ThemeMode.system, ReadingTheme.paper),
        );
      },
    );

    testWidgets('the app follows the chosen theme mode', (tester) async {
      final settings = AppearanceSettings(themeMode: ThemeMode.dark);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appearanceSettingsProvider.overrideWith((ref) => settings),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
            shareIntentSourceProvider.overrideWithValue(_NoShares()),
          ],
          child: const CorplexApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      settings.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      await _disposeTree(tester);
    });
  });

  group('contents', () {
    final outline = [
      PdfOutlineNode(
        title: 'Introduction',
        dest: const PdfDest(1, PdfDestCommand.xyz, null),
        children: [
          PdfOutlineNode(
            title: 'Motivation',
            dest: const PdfDest(2, PdfDestCommand.xyz, null),
            children: const [],
          ),
        ],
      ),
      const PdfOutlineNode(
        title: 'Untargeted heading',
        dest: null,
        children: [],
      ),
      PdfOutlineNode(
        title: 'Results',
        dest: const PdfDest(7, PdfDestCommand.xyz, null),
        children: const [],
      ),
    ];

    test('the outline is flattened with depth and page', () {
      final flat = ContentsSheet.flatten(outline);
      expect(flat.map((e) => (e.title, e.depth, e.page)), [
        ('Introduction', 0, 1),
        ('Motivation', 1, 2),
        ('Untargeted heading', 0, null),
        ('Results', 0, 7),
      ]);
    });

    testWidgets('choosing an entry returns its page', (tester) async {
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => chosen = await showModalBottomSheet<int>(
                  context: context,
                  builder: (_) => ContentsSheet(outline: outline),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Untargeted heading'));
      await tester.pumpAndSettle();
      expect(
        find.text('Untargeted heading'),
        findsOneWidget,
        reason: 'no page: not tappable',
      );
      await tester.tap(find.text('Results'));
      await tester.pumpAndSettle();
      expect(chosen, 7);
    });
  });

  test('ratings: set, change, clear, and stay within 1–5', () async {
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('p'), title: 'T'));
    Future<int?> rating() async => (await (db.select(
      db.papers,
    )..where((p) => p.id.equals('p'))).getSingle()).rating;

    await setRating(db, 'p', 4);
    expect(await rating(), 4);
    await setRating(db, 'p', 9);
    expect(await rating(), 5);
    await setRating(db, 'p', null);
    expect(await rating(), isNull);
  });

  group('all highlights', () {
    test('grouped by paper title, pages in order; search covers quote, comment and title', () async {
      await seed();
      final all = await db.select(db.highlights).join([
        innerJoin(db.papers, db.papers.id.equalsExp(db.highlights.paperId)),
      ]).get();
      expect(all, hasLength(3));

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final done = Completer();
      final sub = container.listen(allHighlightsProvider, (_, next) {
        if (next.value?.length == 3 && !done.isCompleted) done.complete();
      }, fireImmediately: true);
      addTearDown(sub.close);
      await done.future;
      final list = container.read(allHighlightsProvider).value!;
      expect(list.map((e) => e.highlight.quote), [
        'early passage',
        'late passage',
        'gradient descent',
      ]);

      expect(filterHighlights(list, 'REMEMBER').map((e) => e.highlight.id), [
        '3',
      ]);
      expect(filterHighlights(list, 'beta').map((e) => e.highlight.id), ['1']);
      expect(filterHighlights(list, 'passage'), hasLength(2));
      expect(filterHighlights(list, '  '), hasLength(3));
    });

    testWidgets(
      'the screen lists them under their papers and filters as you type',
      (tester) async {
        await seed();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: const MaterialApp(home: AllHighlightsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Alpha paper'), findsOneWidget);
        expect(find.text('Beta paper'), findsOneWidget);
        expect(find.text('early passage'), findsOneWidget);
        expect(find.textContaining('remember this'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'gradient');
        await tester.pumpAndSettle();
        expect(find.text('gradient descent'), findsOneWidget);
        expect(find.text('early passage'), findsNothing);

        await tester.enterText(find.byType(TextField), 'zzz');
        await tester.pumpAndSettle();
        expect(find.text('No matches.'), findsOneWidget);
        await _disposeTree(tester);
      },
    );

    testWidgets('empty library says what to do', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: AllHighlightsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No highlights yet'), findsOneWidget);
      await _disposeTree(tester);
    });
  });

  testWidgets(
    'large text (accessibility sizes) does not overflow the main screens',
    (tester) async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p'),
              title: 'A rather long paper title that will wrap at large text sizes',
              authors: const Value(
                'Vaswani, Ashish; Shazeer, Noam; Parmar, Niki',
              ),
              rating: const Value(4),
            ),
          );
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
            shareIntentSourceProvider.overrideWithValue(_NoShares()),
          ],
          child: const CorplexApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'notes tab');
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'library tab');
      expect(
        find.textContaining('★★★★'),
        findsOneWidget,
        reason: 'the rating shows on the card',
      );
      await _disposeTree(tester);
    },
  );
}
