import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/library/papers_providers.dart';
import 'package:corplex/features/library/views/board_view.dart';
import 'package:corplex/features/library/views/table_view.dart';
import 'package:corplex/features/projects/calendar.dart';
import 'package:corplex/features/projects/timeline.dart';
import 'package:corplex/features/projects/chapters.dart';

import '../../support/mac_screenshot.dart';

class _Host extends ConsumerWidget {
  const _Host(this.table, this.opened);
  final bool table;
  final List<String> opened;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papers = ref.watch(papersListProvider).value ?? const <Paper>[];
    void open(Paper p) => opened.add(p.id);
    return table
        ? PapersTable(papers: papers, onOpen: open)
        : ReadingBoard(papers: papers, onOpen: open);
  }
}

Future<void> _paper(
  AppDatabase db,
  String id,
  String title, {
  ReadingStatus? status,
  int? year,
}) => db
    .into(db.papers)
    .insert(
      PapersCompanion.insert(
        id: Value(id),
        title: title,
        year: Value(year),
        readingStatus: Value(status),
      ),
    );

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Widget _app(AppDatabase db, Widget child) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp(home: Scaffold(body: child)),
);

Future<ReadingStatus?> _status(AppDatabase db, String id) async =>
    (await (db.select(
      db.papers,
    )..where((p) => p.id.equals(id))).getSingle()).readingStatus;

void main() {
  late AppDatabase db;
  setUpAll(() async {
    await loadMacFonts();
    await initializeDateFormatting('en');
  });
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() => db.close());

  testWidgets('board: drag moves a card, one write, Undo restores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _paper(db, 'a', 'Place cells', status: ReadingStatus.toRead);
    await _paper(db, 'b', 'Grid cells', status: ReadingStatus.done);
    await tester.pumpWidget(_app(db, _Host(false, [])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-col-none')), findsNothing);

    final from = tester.getCenter(find.byKey(const ValueKey('board-card-a')));
    final to = tester.getCenter(
      find.byKey(const ValueKey('board-col-reading')),
    );
    final g = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(await _status(db, 'a'), ReadingStatus.reading);
    expect(find.textContaining('Moved'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await _status(db, 'a'), ReadingStatus.toRead);
    await _dispose(tester);
  });

  testWidgets('board on a phone: swipeable columns and a move menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _paper(db, 'a', 'Place cells', status: ReadingStatus.toRead);
    await tester.pumpWidget(_app(db, _Host(false, [])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-pages')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-move-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(await _status(db, 'a'), ReadingStatus.done);
    await _dispose(tester);
  });

  testWidgets('table (Mac): sort by header, keys open, inline edits', (
    tester,
  ) async {
    useMacWindow(tester, const Size(1280, 800));
    await _paper(db, 'a', 'Beta', year: 2020);
    await _paper(db, 'b', 'Alpha', year: 2022);
    await _paper(db, 'c', 'Gamma', year: 2010);
    final opened = <String>[];
    await tester.pumpWidget(_app(db, _Host(true, opened)));
    await tester.pumpAndSettle();

    double y(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('table-title-$id'))).dy;
    expect(y('b') < y('a') && y('a') < y('c'), isTrue); // by title
    await tester.tap(find.byKey(const ValueKey('table-header-year')));
    await tester.pumpAndSettle();
    expect(y('c') < y('a') && y('a') < y('b'), isTrue);
    await tester.tap(find.byKey(const ValueKey('table-header-year')));
    await tester.pumpAndSettle();
    expect(y('b') < y('a') && y('a') < y('c'), isTrue); // descending

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['a']);

    await tester.tap(find.byKey(const ValueKey('table-star-c-4')));
    await tester.pumpAndSettle();
    final c = await (db.select(
      db.papers,
    )..where((p) => p.id.equals('c'))).getSingle();
    expect(c.rating, 4);
    await tester.tap(find.byKey(const ValueKey('table-status-c')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    expect(await _status(db, 'c'), ReadingStatus.reading);
    expect(opened, ['a']); // inline edits don't open the paper
    expect(find.byKey(const ValueKey('table-pick-species')), findsNothing);
    await _dispose(tester);
  }, variant: macOnly);

  testWidgets('table offers study columns once a paper has details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('a'),
            title: 'Rats',
            species: const Value('rat'),
          ),
        );
    await tester.pumpWidget(_app(db, _Host(true, [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('table-pick-species')));
    await tester.pumpAndSettle();
    expect(find.text('rat'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('calendar: day lists items and opens that day\'s note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('d1'),
            title: const Value('Daily one'),
            dailyDate: const Value('2026-03-05'),
          ),
        );
    await _paper(db, 'p', 'Added paper');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: CalendarScreen(today: DateTime(2026, 3, 20))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cal-day-2026-03-05')));
    await tester.pumpAndSettle();
    expect(find.text('Daily one'), findsOneWidget);
    expect(find.text('Open note for this day'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cal-day-2026-03-07')));
    await tester.pumpAndSettle();
    expect(find.text('New note for this day'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cal-next')));
    await tester.pumpAndSettle();
    expect(find.text('April 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cal-day-2026-04-07')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('March 2026'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets(
    'calendar: "New note for this day" makes that day\'s daily note',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: CalendarScreen(today: DateTime(2026, 3, 20)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cal-day-2026-03-07')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('cal-open-day')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      final notes = await db.select(db.notes).get();
      expect(notes.single.dailyDate, '2026-03-07');
      await _dispose(tester);
    },
  );

  testWidgets('timeline: summary, markers, only for applicable projects', (
    tester,
  ) async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: const Value('pr'),
            name: 'T',
            dueDate: Value(DateTime(2026, 3, 14)),
          ),
        );
    final project = await (db.select(db.projects)).getSingle();
    await db.into(db.notes).insert(NotesCompanion.insert(id: const Value('n')));
    final note = await db.select(db.notes).getSingle();
    final chapters = [
      Chapter(
        note: note,
        status: ChapterStatus.draft,
        wordTarget: 1000,
        words: 400,
        position: 0,
      ),
    ];
    expect(timelineApplies(project, chapters), isTrue);
    expect(timelineApplies(project, const []), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProviderScope(
            child: ChapterTimeline(
              project: project,
              chapters: chapters,
              now: DateTime(2026, 3, 4),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('400 / 1,000 words · needs ~60 words/day'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('timeline-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-due')), findsOneWidget);
    await _dispose(tester);
  });
}
