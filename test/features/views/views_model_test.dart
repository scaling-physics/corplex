import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/library/study_details.dart';
import 'package:corplex/features/library/views/views_model.dart';
import 'package:corplex/features/notes/daily_notes.dart';
import 'package:corplex/features/projects/calendar.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:corplex/features/projects/timeline.dart';

late AppDatabase db;

Future<Paper> paper(
  String id,
  String title, {
  int? year,
  String? venue,
  ReadingStatus? status,
  int? rating,
  String? species,
  int? n,
  DateTime? created,
}) async {
  await db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          id: Value(id),
          title: title,
          year: Value(year),
          venue: Value(venue),
          readingStatus: Value(status),
          rating: Value(rating),
          species: Value(species),
          sampleSize: Value(n),
          createdAt: created == null ? const Value.absent() : Value(created),
        ),
      );
  return (db.select(db.papers)..where((p) => p.id.equals(id))).getSingle();
}

Future<Chapter> chapter(String id, int words, int? target) async {
  await db.into(db.notes).insert(NotesCompanion.insert(id: Value(id)));
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(id))).getSingle();
  return Chapter(
    note: note,
    status: null,
    wordTarget: target,
    words: words,
    position: null,
  );
}

Future<Project> project() async {
  await db
      .into(db.projects)
      .insert(
        ProjectsCompanion.insert(
          id: const Value('pr'),
          name: 'Thesis',
          dueDate: Value(DateTime(2026, 3, 5)),
        ),
      );
  return (db.select(db.projects)..where((p) => p.id.equals('pr'))).getSingle();
}

void main() {
  setUp(() => db = AppDatabase.inMemoryForTesting());
  tearDown(() => db.close());
  test('board columns: no-status column only when needed', () async {
    final cols = boardColumns([
      await paper('a', 'A', status: ReadingStatus.done),
      await paper('b', 'B'),
      await paper('c', 'C', status: ReadingStatus.toRead),
    ]);
    expect(cols.map((c) => c.status), [
      ReadingStatus.toRead,
      ReadingStatus.reading,
      ReadingStatus.done,
      null,
    ]);
    expect(cols[2].papers.single.id, 'a');
    expect(
      boardColumns([await paper('z', 'Z', status: ReadingStatus.done)]).length,
      3,
    );
  });

  test('sorting is stable, both ways, empty values last', () async {
    final ps = [
      await paper('a', 'b', year: 2020),
      await paper('b', 'A'),
      await paper('c', 'c', year: 2020),
      await paper('d', 'd', year: 2010),
    ];
    expect(sortPapers(ps, BaseColumn.year).map((p) => p.id), [
      'd',
      'a',
      'c',
      'b',
    ]);
    expect(sortPapers(ps, BaseColumn.year, ascending: false).map((p) => p.id), [
      'a',
      'c',
      'd',
      'b',
    ]);
    expect(sortPapers(ps, BaseColumn.title).map((p) => p.id), [
      'b',
      'a',
      'c',
      'd',
    ]);
    expect(
      sortPapers([
        await paper('x', 'x', n: 30),
        await paper('y', 'y', n: 4),
      ], const StudyColumn(StudyField.sampleSize)).map((p) => p.id),
      ['y', 'x'],
    );
  });

  test('study columns offered only with study details', () async {
    expect(offeredStudyColumns([await paper('a', 'A')]), isEmpty);
    expect(
      offeredStudyColumns([await paper('a2', 'A', species: 'rat')]),
      StudyField.values,
    );
  });

  test('markdown and csv copy', () async {
    final ps = [
      await paper(
        'a',
        'Pipes | bars',
        year: 2020,
        status: ReadingStatus.done,
        rating: 3,
      ),
      await paper('b', 'Commas, "quotes"'),
    ];
    final cols = [
      BaseColumn.title,
      BaseColumn.year,
      BaseColumn.status,
      BaseColumn.rating,
    ];
    final heads = ['Title', 'Year', 'Status', 'Rating'];
    expect(
      papersToMarkdown(ps, cols, heads).split('\n')[2],
      r'| Pipes \| bars | 2020 | Done | ★★★ |',
    );
    expect(
      papersToCsv(ps, cols, heads).split('\n')[2],
      '"Commas, ""quotes""",,,',
    );
  });

  test('calendar collects daily, created, papers and due dates', () async {
    final items = collectCalendarItems(
      notes: [
        (
          id: 'd',
          title: 'Daily',
          createdAt: DateTime(2026, 3, 9),
          dailyDate: '2026-03-05',
        ),
        (
          id: 'n',
          title: 'Note',
          createdAt: DateTime(2026, 3, 5, 14),
          dailyDate: null,
        ),
      ],
      papers: [
        await paper('p', 'Paper', created: DateTime(2026, 3, 5, 23, 59)),
      ],
      projects: [await project()],
    );
    expect(items['2026-03-05']!.map((i) => i.kind).toSet(), {
      CalendarKind.daily,
      CalendarKind.note,
      CalendarKind.paper,
      CalendarKind.due,
    });
    expect(items['2026-03-09'], isNull); // a daily note shows only on its day
  });

  test('month grid starts on the locale weekday', () async {
    // March 2026 starts on a Sunday.
    final sun = monthGrid(DateTime(2026, 3), 0);
    expect(sun.first, DateTime(2026, 3, 1));
    expect(sun.length, 35);
    final mon = monthGrid(DateTime(2026, 3), 1);
    expect(mon.first, DateTime(2026, 2, 23));
    expect(mon.length % 7, 0);
    expect(mon.last, DateTime(2026, 4, 5));
    expect(dailyKey(sun.last), '2026-04-04');
  });

  test('timeline pace', () async {
    final chapters = [
      await chapter('a', 12400, 20000),
      await chapter('b', 0, 20000),
    ];
    final p = timelinePace(
      chapters,
      DateTime(2026, 3, 14),
      DateTime(2026, 2, 12),
    );
    expect(p.words, 12400);
    expect(p.target, 40000);
    expect(p.daysLeft, 30);
    expect(p.wordsPerDay, 920); // 27,600 left over 30 days
    expect(
      timelinePace(
        chapters,
        DateTime(2026, 2, 1),
        DateTime(2026, 2, 12),
      ).pastDue,
      isTrue,
    );
    expect(
      timelinePace(chapters, null, DateTime(2026, 2, 12)).wordsPerDay,
      isNull,
    );
    expect(
      timelinePace(
        [await chapter('c', 5, null)],
        DateTime(2026, 3, 1),
        DateTime(2026, 2, 1),
      ).wordsPerDay,
      isNull,
    );
    expect(
      todayFraction(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 11),
        DateTime(2026, 1, 6),
      ),
      closeTo(0.5, 0.001),
    );
  });
}
