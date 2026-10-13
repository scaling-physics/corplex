import 'dart:convert';
import 'dart:math';

import 'package:flutter_quill/quill_delta.dart';

/// Numbered figures and tables are *stored* as plain text, like citations
/// and maths, so sync, merging, search and old app versions only ever see
/// text:
///
/// * a caption **definition** is a paragraph that starts with
///   `{#fig:LABEL}` (or `{#tbl:LABEL}`) followed by the caption text;
/// * a **reference** is `{@fig:LABEL}` / `{@tbl:LABEL}` anywhere in text.
///
/// The editor shows both as chips reading "Figure 3.2" ([figuresToEmbeds]
/// on load, [figureEmbedsToText] on save). Numbers are never stored: they
/// come from the order of definitions, so they stay right when figures or
/// chapters move.
const figureDefType = 'figdef';
const figureRefType = 'figref';

/// Which numbering a caption belongs to; figures and tables count apart.
enum FigureKind {
  figure('fig', 'Figure', 'List of figures'),
  table('tbl', 'Table', 'List of tables');

  const FigureKind(this.tag, this.title, this.listTitle);

  /// The `fig` / `tbl` in the markers.
  final String tag;

  /// "Figure" / "Table", as shown before the number.
  final String title;
  final String listTitle;

  static FigureKind? fromTag(String tag) {
    for (final k in values) {
      if (k.tag == tag) return k;
    }
    return null;
  }
}

/// A `{#…}` or `{@…}` marker found in text.
class FigureMarker {
  const FigureMarker(
    this.kind,
    this.label,
    this.isDefinition,
    this.start,
    this.end,
  );

  final FigureKind kind;
  final String label;
  final bool isDefinition;

  /// Offsets of the opening `{` and past the closing `}`.
  final int start;
  final int end;
}

final _marker = RegExp(r'\{([#@])(fig|tbl):([A-Za-z0-9_-]+)\}');

String figureDefMarker(FigureKind kind, String label) =>
    '{#${kind.tag}:$label}';

String figureRefMarker(FigureKind kind, String label) =>
    '{@${kind.tag}:$label}';

/// The marker that [text] is exactly, or null.
FigureMarker? parseFigureMarker(String text) {
  final m = _marker.firstMatch(text);
  if (m == null || m.start != 0 || m.end != text.length) return null;
  return FigureMarker(
    FigureKind.fromTag(m.group(2)!)!,
    m.group(3)!,
    m.group(1) == '#',
    0,
    text.length,
  );
}

/// A short random label for a new caption.
String newFigureLabel([Random? random]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = random ?? Random();
  return String.fromCharCodes([
    for (var i = 0; i < 5; i++) chars.codeUnitAt(r.nextInt(chars.length)),
  ]);
}

/// The markers in [s]. A definition only counts at the start of a line
/// (index 0 counts when [lineStart]); elsewhere `{#fig:x}` is just text.
List<FigureMarker> findFigureMarkers(String s, {bool lineStart = true}) {
  final out = <FigureMarker>[];
  for (final m in _marker.allMatches(s)) {
    final isDef = m.group(1) == '#';
    if (isDef) {
      final atStart = m.start == 0 ? lineStart : s[m.start - 1] == '\n';
      if (!atStart) continue;
    }
    out.add(
      FigureMarker(
        FigureKind.fromTag(m.group(2)!)!,
        m.group(3)!,
        isDef,
        m.start,
        m.end,
      ),
    );
  }
  return out;
}

/// [text] with every reference replaced by what [nameOf] says ("Figure 3.2"),
/// definitions left alone.
String replaceFigureRefs(
  String text,
  String Function(FigureKind kind, String label) nameOf,
) {
  if (!text.contains('{@')) return text;
  return text.replaceAllMapped(_marker, (m) {
    if (m.group(1) != '@') return m.group(0)!;
    return nameOf(FigureKind.fromTag(m.group(2)!)!, m.group(3)!);
  });
}

List<Map<String, Object?>>? _ops(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return null;
    return [for (final op in decoded) (op as Map).cast<String, Object?>()];
  } on FormatException {
    return null;
  }
}

/// Stored note content → the editor's form, with figure and table markers
/// as embeds. Content that isn't Delta JSON is returned unchanged.
String figuresToEmbeds(String stored) {
  if (!stored.contains('{#') && !stored.contains('{@')) return stored;
  final ops = _ops(stored);
  if (ops == null) return stored;
  final out = <Map<String, Object?>>[];
  var lineStart = true;
  for (final op in ops) {
    final insert = op['insert'];
    if (insert is! String) {
      out.add(op);
      lineStart = false;
      continue;
    }
    final attributes = op['attributes'];
    final inCode = attributes is Map && attributes.containsKey('code');
    final markers = inCode
        ? const <FigureMarker>[]
        : findFigureMarkers(insert, lineStart: lineStart);
    Map<String, Object?> make(Object value) => {
      'insert': value,
      'attributes': ?attributes,
    };
    var pos = 0;
    for (final m in markers) {
      if (m.start > pos) out.add(make(insert.substring(pos, m.start)));
      out.add(
        make({
          m.isDefinition ? figureDefType : figureRefType: insert.substring(
            m.start,
            m.end,
          ),
        }),
      );
      pos = m.end;
    }
    if (pos < insert.length) out.add(make(insert.substring(pos)));
    lineStart = insert.endsWith('\n');
  }
  return jsonEncode(out);
}

/// The editor's content → stored form: figure embeds back to marker text.
/// Raw Delta JSON; pass it through the editor's normalising save step.
String figureEmbedsToText(String editorContent) {
  if (!editorContent.contains('"$figureDefType"') &&
      !editorContent.contains('"$figureRefType"')) {
    return editorContent;
  }
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  return jsonEncode([
    for (final op in ops)
      if (op['insert']
          case {figureDefType: final String marker} ||
              {figureRefType: final String marker})
        {'insert': marker, 'attributes': ?op['attributes']}
      else
        op,
  ]);
}

/// A caption definition found in a document.
class FigureDef {
  const FigureDef(this.kind, this.label, this.caption, this.offset);

  final FigureKind kind;
  final String label;

  /// The rest of the line, with references and citations as marker text.
  final String caption;

  /// Where the definition's chip sits in the document.
  final int offset;
}

/// The definitions in an *editor-form* [delta] (markers as embeds), in
/// order, with offsets as the editor counts them (an embed is one
/// character).
List<FigureDef> figureDefsIn(Delta delta) {
  final out = <FigureDef>[];
  FigureKind? kind;
  String? label;
  var at = 0;
  var caption = StringBuffer();
  void close() {
    if (kind != null) {
      out.add(FigureDef(kind!, label!, caption.toString().trim(), at));
    }
    kind = null;
  }

  var offset = 0;
  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    final data = op.data;
    if (data is Map) {
      if (data[figureDefType] case final String marker) {
        close();
        final m = parseFigureMarker(marker);
        if (m != null) {
          kind = m.kind;
          label = m.label;
          at = offset;
          caption = StringBuffer();
        }
      } else if (kind != null) {
        if (data[figureRefType] ?? data['cite'] case final String marker) {
          caption.write(marker);
        } else if (data['math'] case final String tex) {
          caption.write('\$$tex\$');
        }
      }
      offset += 1;
      continue;
    }
    final text = data as String;
    offset += text.length;
    if (kind == null) continue;
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      caption.write(parts[i]);
      if (i < parts.length - 1) close();
    }
  }
  close();
  return out;
}
