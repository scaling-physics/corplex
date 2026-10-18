import 'dart:convert';

/// Quill block-embed type for a table in a note. The embed's data is the
/// encoded [NoteTable], so a table lives in the note's content and syncs,
/// versions and merges with the text around it. Like a drawing, it sits on
/// a line of its own (insert the newlines yourself — Quill's
/// `InsertEmbedsRule` only adds them for videos).
const tableEmbedType = 'table';

/// A simple table: rows of plain-text cells, the first row optionally a
/// header. Every row has the same number of cells ([columns]).
class NoteTable {
  NoteTable({required List<List<String>> rows, this.header = true})
    : rows = _rectangular(rows);

  /// An empty table with [columnCount] columns and [rowCount] rows (the
  /// first a header).
  factory NoteTable.empty({int rowCount = 3, int columnCount = 3}) =>
      NoteTable(
        rows: [
          for (var r = 0; r < rowCount; r++)
            [for (var c = 0; c < columnCount; c++) ''],
        ],
      );

  /// Never throws: damaged data gives a 1×1 empty table rather than
  /// breaking the note.
  factory NoteTable.decode(String data) {
    try {
      final json = jsonDecode(data) as Map<String, Object?>;
      final rows = [
        for (final r in (json['r'] as List? ?? const []))
          [for (final c in (r as List)) c?.toString() ?? ''],
      ];
      return NoteTable(
        rows: rows.isEmpty ? [['']] : rows,
        header: json['h'] != false,
      );
    } catch (_) {
      return NoteTable(rows: [['']]);
    }
  }

  final List<List<String>> rows;
  final bool header;

  int get columns => rows.isEmpty ? 0 : rows.first.length;

  String encode() => jsonEncode({'v': 1, 'h': header, 'r': rows});

  /// The cells as text for search, word counts and previews: cells joined
  /// by tabs, rows by newlines.
  String get plainText => rows.map((r) => r.join('\t')).join('\n');

  NoteTable copyWith({List<List<String>>? rows, bool? header}) =>
      NoteTable(rows: rows ?? this.rows, header: header ?? this.header);

  static List<List<String>> _rectangular(List<List<String>> rows) {
    final width = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
    return [
      for (final r in rows) [...r, for (var i = r.length; i < width; i++) ''],
    ];
  }
}
