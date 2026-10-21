import '../../../data/database.dart';
import '../../../data/tables/papers_table.dart' show ReadingStatus;
import '../authors.dart';
import '../study_details.dart';

/// Board columns: a status, or null for "No status".
typedef BoardColumn = ({ReadingStatus? status, List<Paper> papers});

/// To read / Reading / Done, plus "No status" only when some paper has none.
/// Papers keep the order they came in.
List<BoardColumn> boardColumns(List<Paper> papers) {
  List<Paper> of(ReadingStatus? s) => [
    for (final p in papers)
      if (p.readingStatus == s) p,
  ];
  return [
    (status: ReadingStatus.toRead, papers: of(ReadingStatus.toRead)),
    (status: ReadingStatus.reading, papers: of(ReadingStatus.reading)),
    (status: ReadingStatus.done, papers: of(ReadingStatus.done)),
    if (papers.any((p) => p.readingStatus == null))
      (status: null, papers: of(null)),
  ];
}

/// A table column: a built-in one or a study field.
sealed class TableColumn {
  const TableColumn();
  String get id;
}

class BaseColumn extends TableColumn {
  const BaseColumn._(this.id);
  @override
  final String id;

  static const title = BaseColumn._('title');
  static const authors = BaseColumn._('authors');
  static const year = BaseColumn._('year');
  static const venue = BaseColumn._('venue');
  static const status = BaseColumn._('status');
  static const rating = BaseColumn._('rating');
  static const all = [title, authors, year, venue, status, rating];
}

class StudyColumn extends TableColumn {
  const StudyColumn(this.field);
  final StudyField field;
  @override
  String get id => 'study:${field.key}';
  @override
  bool operator ==(Object other) =>
      other is StudyColumn && other.field == field;
  @override
  int get hashCode => field.hashCode;
}

/// Study columns are only offered once some paper has study details.
List<StudyField> offeredStudyColumns(List<Paper> papers) =>
    papers.any(hasStudyDetails) ? StudyField.values : const [];

int _statusRank(ReadingStatus? s) => s == null ? 3 : s.index;

bool _isEmpty(Paper p, TableColumn c) {
  if (c is StudyColumn) return studyValue(p, c.field).isEmpty;
  return switch (c.id) {
    'authors' => p.authors.trim().isEmpty,
    'year' => p.year == null,
    'venue' => (p.venue ?? '').trim().isEmpty,
    'status' => p.readingStatus == null,
    'rating' => p.rating == null,
    _ => false,
  };
}

int _compare(Paper a, Paper b, TableColumn c) {
  if (c is StudyColumn) {
    if (c.field == StudyField.sampleSize) {
      return a.sampleSize!.compareTo(b.sampleSize!);
    }
    return studyValue(
      a,
      c.field,
    ).toLowerCase().compareTo(studyValue(b, c.field).toLowerCase());
  }
  return switch (c.id) {
    'authors' => a.authors.toLowerCase().compareTo(b.authors.toLowerCase()),
    'year' => a.year!.compareTo(b.year!),
    'venue' => a.venue!.toLowerCase().compareTo(b.venue!.toLowerCase()),
    'status' => _statusRank(
      a.readingStatus,
    ).compareTo(_statusRank(b.readingStatus)),
    'rating' => a.rating!.compareTo(b.rating!),
    _ => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  };
}

/// Sorted copy, stable: ties keep their incoming order. Empty values sort
/// last in either direction.
List<Paper> sortPapers(
  List<Paper> papers,
  TableColumn column, {
  bool ascending = true,
}) {
  final indexed = [for (final (i, p) in papers.indexed) (i, p)];
  indexed.sort((x, y) {
    final ex = _isEmpty(x.$2, column), ey = _isEmpty(y.$2, column);
    if (ex != ey) return ex ? 1 : -1;
    var c = ex ? 0 : _compare(x.$2, y.$2, column);
    if (!ascending) c = -c;
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Plain text of a cell (English status words; used by copy/export).
String cellText(Paper p, TableColumn c) {
  if (c is StudyColumn) return studyValue(p, c.field);
  return switch (c.id) {
    'authors' => p.authors.isEmpty ? '' : displayAuthors(p.authors),
    'year' => p.year?.toString() ?? '',
    'venue' => p.venue ?? '',
    'status' => switch (p.readingStatus) {
      ReadingStatus.toRead => 'To read',
      ReadingStatus.reading => 'Reading',
      ReadingStatus.done => 'Done',
      null => '',
    },
    'rating' => p.rating == null ? '' : '★' * p.rating!,
    _ => p.title,
  };
}

List<List<String>> _grid(
  List<Paper> papers,
  List<TableColumn> columns,
  List<String> headers,
) => [
  headers,
  for (final p in papers) [for (final c in columns) cellText(p, c)],
];

String papersToMarkdown(
  List<Paper> papers,
  List<TableColumn> columns,
  List<String> headers,
) {
  String esc(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');
  final rows = _grid(papers, columns, headers);
  String line(List<String> r) => '| ${r.map(esc).join(' | ')} |';
  return [
    line(rows.first),
    '| ${[for (final _ in columns) '---'].join(' | ')} |',
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}

String papersToCsv(
  List<Paper> papers,
  List<TableColumn> columns,
  List<String> headers,
) {
  String q(String s) =>
      s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  return _grid(
    papers,
    columns,
    headers,
  ).map((r) => r.map(q).join(',')).join('\n');
}
