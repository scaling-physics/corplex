// On-device performance run with a large library (1,500 papers, 3,000 notes,
// 20,000 highlights, generated PDFs up to 300 pages). Prints `PERFDEV ...`
// lines; asserts only generous ceilings.
//
//   flutter test integration_test/perf_test.dart -d emulator-5554 --profile
//   flutter test integration_test/perf_test.dart -d macos --profile
//
// (`--profile` where the platform supports it; debug numbers are several
// times worse and say so in their header.) Seeding takes a while on a
// phone; it happens once, before the first measurement.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/home/open_card.dart';
import 'package:corplex/theme/motion_widgets.dart' show EmptyState;
import 'package:corplex/features/ocr/pdf_pages.dart';
import 'package:corplex/features/search/pdf_text_index.dart';
import 'package:corplex/features/search/search_index.dart';
import 'package:corplex/features/search/search_screen.dart';
import 'package:corplex/features/settings/appearance_settings.dart';
import 'package:corplex/features/sync/transfer_settings.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../test/perf/seed_library.dart';

const _words = [
  'neural',
  'cortex',
  'learning',
  'memory',
  'attention',
  'transformer',
  'hippocampus',
  'synaptic',
  'plasticity',
  'network',
  'gradient',
  'language',
];

void _log(String name, String value) {
  // ignore: avoid_print
  print('PERFDEV ${name.padRight(46)} $value');
}

String _ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';

/// A PDF of [pages] pages of running text, so extraction has real work.
Future<File> _makePdf(Directory dir, String name, int pages) async {
  final random = Random(pages);
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    final paragraph = [
      for (var w = 0; w < 260; w++) _words[random.nextInt(_words.length)],
    ].join(' ');
    doc.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Page ${i + 1}', style: const pw.TextStyle(fontSize: 18)),
            pw.SizedBox(height: 8),
            pw.Paragraph(text: paragraph),
          ],
        ),
      ),
    );
  }
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(await doc.save());
  return file;
}

class _Frames {
  final List<FrameTiming> timings = [];
  void _on(List<FrameTiming> t) => timings.addAll(t);
  void start() => SchedulerBinding.instance.addTimingsCallback(_on);
  void stop() => SchedulerBinding.instance.removeTimingsCallback(_on);

  void report(String name) {
    if (timings.isEmpty) {
      _log(name, 'no frames');
      return;
    }
    double pct(List<double> v, double p) => v[((v.length - 1) * p).round()];
    final build = [
      for (final t in timings) t.buildDuration.inMicroseconds / 1000,
    ]..sort();
    final raster = [
      for (final t in timings) t.rasterDuration.inMicroseconds / 1000,
    ]..sort();
    final janky = timings
        .where(
          (t) =>
              t.buildDuration.inMicroseconds / 1000 > 16.7 ||
              t.rasterDuration.inMicroseconds / 1000 > 16.7,
        )
        .length;
    _log(
      name,
      'frames=${timings.length} janky=$janky '
      'build p50=${pct(build, .5).toStringAsFixed(1)} '
      'p90=${pct(build, .9).toStringAsFixed(1)} '
      'p99=${pct(build, .99).toStringAsFixed(1)} '
      'max=${build.last.toStringAsFixed(1)} | '
      'raster p50=${pct(raster, .5).toStringAsFixed(1)} '
      'p90=${pct(raster, .9).toStringAsFixed(1)} '
      'p99=${pct(raster, .99).toStringAsFixed(1)} '
      'max=${raster.last.toStringAsFixed(1)} ms',
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late Directory dir;
  late AppDatabase db;
  late SeededLibrary lib;
  late List<File> pdfs;
  var seeded = false;

  Future<void> ensureSeeded() async {
    if (seeded) return;
    seeded = true;
    _log(
      'mode',
      kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'DEBUG (numbers are not representative)',
    );
    dir = await Directory.systemTemp.createTemp('corplex-perf');
    final watch = Stopwatch()..start();
    pdfs = [
      await _makePdf(dir, 'big.pdf', 300),
      for (var i = 0; i < 3; i++) await _makePdf(dir, 'small$i.pdf', 30),
    ];
    _log('generate PDFs (300 + 3x30 pages)', _ms(watch.elapsed));
    final file = File('${dir.path}/perf.sqlite');
    db = AppDatabase.forTesting(
      NativeDatabase.createInBackground(
        file,
        setup: (d) {
          d.execute('PRAGMA foreign_keys = ON;');
          d.execute('PRAGMA secure_delete = ON;');
        },
      ),
    );
    watch
      ..reset()
      ..start();
    lib = await seedLibrary(
      db,
      pdfPaths: [
        pdfs[0].path,
        for (var i = 1; i < 40; i++) pdfs[1 + i % 3].path,
      ],
    );
    _log('seed library', _ms(watch.elapsed));
  }

  Widget app(TransferSettings transfer, AppearanceSettings appearance) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          transferSettingsProvider.overrideWith((ref) => transfer),
          appearanceSettingsProvider.overrideWith((ref) => appearance),
        ],
        child: const CorplexApp(),
      );

  Finder biggestScrollable() {
    // The tallest vertical list: the notes or papers, not a chip row.
    return find.byWidgetPredicate(
      (w) => w is Scrollable && w.axis == Axis.vertical,
    );
  }

  Future<void> scroll(WidgetTester tester, {int flings = 10}) async {
    final list = biggestScrollable().first;
    for (var i = 0; i < flings; i++) {
      await tester.fling(list, const Offset(0, -700), 2500);
      await tester.pump(const Duration(milliseconds: 700));
    }
    for (var i = 0; i < flings ~/ 2; i++) {
      await tester.fling(list, const Offset(0, 700), 2500);
      await tester.pump(const Duration(milliseconds: 700));
    }
  }

  // A Mac window that is not on screen gets no frames, and every pump would
  // wait forever; the UI measurements need a visible window or a device.
  final macHeadless = Platform.isMacOS;
  // `--dart-define=PERF_ONLY=startup|pdf|search` runs one group.
  const only = String.fromEnvironment('PERF_ONLY');
  bool skipUnless(String group) => only.isNotEmpty && only != group;

  testWidgets(
    'startup and list scrolling with a large library',
    skip: macHeadless || skipUnless('startup'),
    (tester) async {
      await ensureSeeded();
      final transfer = await TransferSettings.load();
      final appearance = await AppearanceSettings.load();
      final frames = _Frames()..start();
      final start = Stopwatch()..start();
      await tester.pumpWidget(app(transfer, appearance));
      var pumps = 0;
      while (find.byType(OpenCard).evaluate().isEmpty && pumps < 600) {
        await tester.pump(const Duration(milliseconds: 16));
        pumps++;
      }
      _log('startup to first note card on screen', _ms(start.elapsed));
      expect(find.byType(OpenCard), findsWidgets);
      await tester.pump(const Duration(seconds: 1));
      frames.stop();
      frames.report('startup frames (incl. first second)');

      final notesFrames = _Frames()..start();
      await scroll(tester);
      await tester.pump(const Duration(milliseconds: 300));
      notesFrames.stop();
      notesFrames.report('scroll Notes list (10 down, 5 up)');

      // Library tab
      final switchWatch = Stopwatch()..start();
      await tester.tap(find.text('Library').last);
      var n = 0;
      while (find.byType(Image).evaluate().isEmpty && n < 100) {
        await tester.pump(const Duration(milliseconds: 16));
        n++;
      }
      await tester.pump(const Duration(milliseconds: 400));
      _log('switch to Library tab', _ms(switchWatch.elapsed));
      final libFrames = _Frames()..start();
      await scroll(tester);
      await tester.pump(const Duration(milliseconds: 300));
      libFrames.stop();
      libFrames.report('scroll Library list (covers on first 40)');

      // Editing a note while the Notes list is alive re-queries it.
      final editWatch = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        await db.customUpdate(
          'UPDATE notes SET title = ? WHERE id = ?',
          variables: [
            Variable.withString('Edited $i'),
            Variable.withString(lib.noteIds[5]),
          ],
          updates: {db.notes},
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      _log('10 note saves with lists alive (wall)', _ms(editWatch.elapsed));
    },
  );

  testWidgets('PDF: open, text, indexing', skip: skipUnless('pdf'), (
    tester,
  ) async {
    await ensureSeeded();
    final watch = Stopwatch()..start();
    final doc = await PdfDocument.openFile(pdfs[0].path);
    _log('open 300-page PDF', _ms(watch.elapsed));
    watch
      ..reset()
      ..start();
    final pages = doc.pages;
    await pages[0].loadStructuredText();
    _log('text of page 1', _ms(watch.elapsed));
    watch
      ..reset()
      ..start();
    await pages[150].loadStructuredText();
    _log('text of page 151', _ms(watch.elapsed));
    watch
      ..reset()
      ..start();
    final page = pages[150];
    final rendered = await page.render(
      width: 1200,
      height: (1200 * page.height / page.width).round(),
      fullWidth: 1200,
      fullHeight: (1200 * page.height / page.width).roundToDouble(),
    );
    rendered?.dispose();
    _log('render page 151 at 1200 px', _ms(watch.elapsed));
    await doc.dispose();

    // Earlier tests may have run the app's own indexer: start from nothing.
    await db.customStatement('DROP TABLE IF EXISTS pdf_pages_index');
    await db.customStatement('DROP TABLE IF EXISTS pdf_index_state');
    final index = PdfTextIndex(db, PdfrxPages.open);
    final frames = _Frames()..start();
    watch
      ..reset()
      ..start();
    final indexing = index.run();
    // Meanwhile the UI keeps animating: a fake scroll of pumped frames.
    var pumped = 0;
    var done = false;
    unawaited(indexing.whenComplete(() => done = true));
    while (!done) {
      if (macHeadless) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      } else {
        await tester.pump(const Duration(milliseconds: 16));
        pumped++;
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    }
    final elapsed = watch.elapsed;
    frames.stop();
    final counted = await db
        .customSelect('SELECT COUNT(*) AS c FROM pdf_pages_index')
        .getSingle();
    final pageCount = counted.read<int>('c');
    _log(
      'PDF full-text index (40 papers, $pageCount pages)',
      '${_ms(elapsed)} = ${(elapsed.inMicroseconds / 1000 / pageCount).toStringAsFixed(2)} ms/page',
    );
    _log('pumped frames while indexing', '$pumped');
    frames.report('frames while indexing');
  });

  testWidgets('search as you type', skip: macHeadless || skipUnless('search'), (
    tester,
  ) async {
    await ensureSeeded();
    final transfer = await TransferSettings.load();
    final appearance = await AppearanceSettings.load();
    await tester.pumpWidget(app(transfer, appearance));
    await tester.pump(const Duration(seconds: 2));

    final cold = Stopwatch()..start();
    final index = SearchIndex(db);
    await index.refresh();
    _log('search index refresh (first, builds index)', _ms(cold.elapsed));
    final warm = Stopwatch()..start();
    await index.refresh();
    _log('search index refresh (warm)', _ms(warm.elapsed));

    await tester.tap(find.byTooltip('Search').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final frames = _Frames()..start();
    const query = 'neural cortex';
    final typing = Stopwatch()..start();
    for (var i = 1; i <= query.length; i++) {
      // The real keyboard owns text input on a device, so drive the field
      // the way a keystroke does: new text, then onChanged.
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(TextField),
        ),
      );
      field.controller!.text = query.substring(0, i);
      field.onChanged!(query.substring(0, i));
      await tester.pump(const Duration(milliseconds: 120));
    }
    var waited = 0;
    while (find.byType(ListTile).evaluate().isEmpty && waited < 600) {
      await tester.pump(const Duration(milliseconds: 16));
      waited++;
    }
    _log('type "$query" until results show', _ms(typing.elapsed));
    await tester.pump(const Duration(milliseconds: 500));
    frames.stop();
    frames.report('frames while typing a search');
    _log('results on screen', '${find.byType(ListTile).evaluate().length}');
    final empty = find.byType(EmptyState).evaluate().length;
    _log('empty states on screen', '$empty');
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(SearchScreen),
        matching: find.byType(TextField),
      ),
    );
    _log('search field text', '"${field.controller?.text}"');
    for (final t in tester.widgetList<Text>(
      find.descendant(of: find.byType(EmptyState), matching: find.byType(Text)),
    )) {
      _log('empty state text', '${t.data}');
    }
    for (final q in ['neur', 'neural cortex', 'transformer attention']) {
      final watch = Stopwatch()..start();
      final hits = await index.search(q);
      _log('index.search "$q"', '${_ms(watch.elapsed)} (${hits.length} hits)');
    }
  });

  tearDownAll(() async {
    if (seeded) {
      // Closing waits for the database isolate; never let teardown hang the run.
      await db.close().timeout(const Duration(seconds: 5), onTimeout: () {});
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  });
}
