import 'dart:convert';

import '../export/vault_export.dart' show sanitizeFileName;
import '../notes/math_markers.dart';
import '../notes/note_highlight.dart' show NoteHighlight;
import '../notes/note_links.dart';
import '../notes/note_table.dart';

/// Markdown (Obsidian flavoured) → the Quill Delta Corplex stores, in the
/// formats fixed by the 1.16 design: note links `corplex://note/<id>` with
/// optional `#heading=` / `#block=` fragments, `noteembed` block embeds,
/// pandoc inline footnotes `^[…]`, maths / citations / `^id` kept as text,
/// tables as `table` embeds. Pure Dart: no database, no files. Links are
/// resolved through an [MdResolver] the importer supplies once every note
/// has an id.

/// A note a link can point at.
class MdNoteRef {
  const MdNoteRef(this.id, this.title);
  final String id;
  final String title;
}

/// Looks up what links point at, for one note being converted.
abstract class MdResolver {
  /// The note named by [target] (a title, alias, path with or without
  /// `.md`; no `#fragment`), or null.
  MdNoteRef? note(String target);

  /// The vault-relative path of a non-note file named by [target], or null.
  String? file(String target);

  /// A short text of the paragraph carrying block id [blockId] in note
  /// [noteId], used as link text, or null.
  String? blockPreview(String noteId, String blockId);
}

/// A resolver that finds nothing (every link stays plain text).
class NoResolver implements MdResolver {
  const NoResolver();
  @override
  MdNoteRef? note(String target) => null;
  @override
  String? file(String target) => null;
  @override
  String? blockPreview(String noteId, String blockId) => null;
}

/// A note's YAML front matter, the parts the importer uses.
class MdFrontmatter {
  const MdFrontmatter({
    this.fields = const {},
    this.tags = const [],
    this.aliases = const [],
    this.locked = false,
    this.citekey,
    this.created,
    this.updated,
  });

  final Map<String, Object?> fields;
  final List<String> tags;
  final List<String> aliases;
  final bool locked;
  final String? citekey;
  final DateTime? created;
  final DateTime? updated;
}

/// The result of [markdownToDelta].
class MdConversion {
  MdConversion({
    required this.ops,
    required this.frontmatter,
    required this.title,
    required this.tags,
    required this.attachments,
    required this.unresolved,
  });

  /// Quill Delta operations (JSON-ready), always ending in a newline.
  final List<Map<String, Object?>> ops;
  final MdFrontmatter frontmatter;

  /// The title: the leading `# Title` when it matches the file name (it is
  /// dropped from the body), else the file name.
  final String title;

  /// Inline `#tags` found in the text (they also stay in the text).
  final Set<String> tags;

  /// Vault paths of files the note links or embeds, in order, unique.
  final List<String> attachments;

  /// Links and embeds that matched nothing and were left as text.
  final int unresolved;

  String get content => jsonEncode(ops);

  /// The text of the document (embeds are `￼`), for comparing notes.
  String get plainText {
    final b = StringBuffer();
    for (final op in ops) {
      final i = op['insert'];
      b.write(i is String ? i : '￼');
    }
    return b.toString();
  }
}

// ---- Front matter ------------------------------------------------------------

/// Splits [text] into its front matter and body. Front matter is only
/// recognised at the very start (after an optional BOM), between `---`
/// lines (the closer may also be `...`).
({MdFrontmatter frontmatter, String body}) splitFrontmatter(String text) {
  var t = text.startsWith('﻿') ? text.substring(1) : text;
  t = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (!t.startsWith('---')) {
    return (frontmatter: const MdFrontmatter(), body: t);
  }
  final lines = t.split('\n');
  if (lines.first.trimRight() != '---') {
    return (frontmatter: const MdFrontmatter(), body: t);
  }
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    final l = lines[i].trimRight();
    if (l == '---' || l == '...') {
      end = i;
      break;
    }
  }
  if (end < 0) return (frontmatter: const MdFrontmatter(), body: t);
  final fm = _parseFrontmatter(lines.sublist(1, end));
  return (frontmatter: fm, body: lines.sublist(end + 1).join('\n'));
}

String _unquote(String v) {
  final s = v.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    final inner = s.substring(1, s.length - 1);
    final b = StringBuffer();
    for (var i = 0; i < inner.length; i++) {
      final c = inner[i];
      if (c == r'\' && i + 1 < inner.length) {
        final n = inner[++i];
        b.write(switch (n) {
          'n' => '\n',
          't' => '\t',
          _ => n,
        });
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }
  if (s.length >= 2 && s.startsWith("'") && s.endsWith("'")) {
    return s.substring(1, s.length - 1).replaceAll("''", "'");
  }
  return s;
}

List<String> _flowList(String v) {
  final inner = v.trim().substring(1, v.trim().length - 1);
  final out = <String>[];
  final cur = StringBuffer();
  String? quote;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (quote != null) {
      cur.write(c);
      if (c == quote && (i == 0 || inner[i - 1] != r'\')) quote = null;
    } else if (c == '"' || c == "'") {
      quote = c;
      cur.write(c);
    } else if (c == ',') {
      out.add(_unquote(cur.toString()));
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(_unquote(cur.toString()));
  return [
    for (final s in out)
      if (s.trim().isNotEmpty) s.trim(),
  ];
}

MdFrontmatter _parseFrontmatter(List<String> lines) {
  final fields = <String, Object?>{};
  final key = RegExp(r'^([A-Za-z0-9_][A-Za-z0-9_\-. ]*?)\s*:(?:\s+(.*))?$');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (line.startsWith(' ') || line.startsWith('\t') || line.startsWith('-')) {
      continue; // a continuation the key below already consumed
    }
    final m = key.firstMatch(line.trimRight());
    if (m == null) continue;
    final name = m.group(1)!.trim().toLowerCase();
    final raw = (m.group(2) ?? '').trim();
    if (raw.isEmpty || raw == '|' || raw == '>' || raw == '|-' || raw == '>-') {
      // A block list, a block scalar, or an empty value.
      final items = <String>[];
      final text = <String>[];
      var j = i + 1;
      while (j < lines.length) {
        final l = lines[j];
        if (l.trim().isEmpty) {
          j++;
          continue;
        }
        final isList = RegExp(r'^\s*-(\s|$)').hasMatch(l);
        final indented = l.startsWith(' ') || l.startsWith('\t');
        if (!isList && !indented) break;
        if (isList) {
          items.add(_unquote(l.trim().substring(1).trim()));
        } else {
          text.add(l.trim());
        }
        j++;
      }
      i = j - 1;
      if (items.isNotEmpty) {
        fields[name] = items;
      } else if (text.isNotEmpty) {
        fields[name] = text.join(raw.startsWith('>') ? ' ' : '\n');
      } else {
        fields[name] = '';
      }
    } else if (raw.startsWith('[') && raw.endsWith(']')) {
      fields[name] = _flowList(raw);
    } else {
      fields[name] = _unquote(raw);
    }
  }

  List<String> asList(Object? v, {required bool splitSpaces}) {
    if (v == null) return const [];
    final raw = v is List
        ? v.map((e) => '$e').toList()
        : '$v'.split(splitSpaces ? RegExp(r'[,\s]+') : RegExp(r','));
    return [
      for (final s in raw)
        if (s.trim().isNotEmpty) s.trim(),
    ];
  }

  final tags = <String>[
    for (final t in [
      ...asList(fields['tags'], splitSpaces: true),
      ...asList(fields['tag'], splitSpaces: true),
    ])
      t.replaceFirst(RegExp(r'^#+'), ''),
  ].where((t) => t.isNotEmpty).toList();
  final aliases = [
    ...asList(fields['aliases'], splitSpaces: false),
    ...asList(fields['alias'], splitSpaces: false),
  ];
  final locked = '${fields['locked']}'.toLowerCase() == 'true';
  final citekey = fields['citekey'];
  return MdFrontmatter(
    fields: fields,
    tags: tags,
    aliases: aliases,
    locked: locked,
    citekey: citekey is String && citekey.isNotEmpty ? citekey : null,
    created: _date(fields['created']),
    updated: _date(fields['updated']),
  );
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v.trim()) : null;

/// The text of a leading `# Title` line (first non-blank line of [body])
/// when it names the same note as [fileTitle] (file-name rules: illegal
/// characters and case ignored), else null.
String? matchingLeadingTitle(String body, String fileTitle) {
  final lines = body.split('\n');
  for (final raw in lines) {
    if (raw.trim().isEmpty) continue;
    final m = RegExp(r'^#\s+(.+?)(?:\s+#+)?\s*$').firstMatch(raw.trimRight());
    if (m == null) return null;
    final h = m.group(1)!.trim();
    String norm(String s) => sanitizeFileName(s).toLowerCase();
    return norm(h) == norm(fileTitle) ? h : null;
  }
  return null;
}

// ---- Converter ---------------------------------------------------------------

typedef _Attrs = Map<String, Object?>;

/// A piece of inline content.
class _Run {
  _Run.text(this.text, [this.attrs = const {}]) : kind = _RunKind.text;
  _Run.attach(this.text) : kind = _RunKind.attach, attrs = const {};
  _Run.drop() : kind = _RunKind.drop, text = '', attrs = const {};

  final _RunKind kind;
  final String text;
  final _Attrs attrs;
}

enum _RunKind { text, attach, drop }

class _Line {
  _Line(this.ops, {this.header, this.isEmbed = false});
  final List<_Attrs> ops;
  final String? header;
  final bool isEmbed;
}

/// Converts [markdown] (the whole file, front matter included).
///
/// [fileTitle] is the file name without `.md`; a leading `# Title` that
/// names the same note is dropped. [selfId] / [selfTitle] let `[[#Heading]]`
/// point at the note itself.
MdConversion markdownToDelta(
  String markdown, {
  MdResolver resolver = const NoResolver(),
  String fileTitle = '',
  String? selfId,
}) {
  final split = splitFrontmatter(markdown);
  final conv = _Converter(resolver, selfId: selfId, fileTitle: fileTitle);
  return conv.run(split.frontmatter, split.body);
}

class _Converter {
  _Converter(this.resolver, {required this.selfId, required this.fileTitle});

  final MdResolver resolver;
  final String? selfId;
  final String fileTitle;

  final tags = <String>{};
  final attachments = <String>[];
  var unresolved = 0;
  final footnotes = <String, String>{};
  late String title;

  MdConversion run(MdFrontmatter fm, String body) {
    title = fileTitle;
    final lead = matchingLeadingTitle(body, fileTitle);
    var lines = _stripComments(body.split('\n'));
    if (lead != null) {
      title = lead;
      final first = lines.indexWhere((l) => l.trim().isNotEmpty);
      lines = lines.sublist(first + 1);
    }
    lines = _takeFootnoteDefinitions(lines);
    final out = _blocks(lines)..removeWhere((l) => l.ops.isEmpty);

    // A heading "Attachments" with nothing under it once its links became
    // attachments (Corplex's own vault export ends that way).
    if (attachments.isNotEmpty &&
        out.isNotEmpty &&
        out.last.header?.trim().toLowerCase() == 'attachments') {
      out.removeLast();
    }

    final ops = <_Attrs>[];
    for (final l in out) {
      ops.addAll(l.ops);
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    return MdConversion(
      ops: _merge(ops),
      frontmatter: fm,
      title: title,
      tags: tags,
      attachments: attachments,
      unresolved: unresolved,
    );
  }

  static List<_Attrs> _merge(List<_Attrs> ops) {
    final out = <_Attrs>[];
    for (final op in ops) {
      final ins = op['insert'];
      if (out.isNotEmpty &&
          ins is String &&
          ins != '\n' &&
          out.last['insert'] is String &&
          !(out.last['insert'] as String).endsWith('\n') &&
          _sameAttrs(out.last['attributes'], op['attributes'])) {
        out.last['insert'] = (out.last['insert'] as String) + ins;
      } else {
        out.add(Map<String, Object?>.of(op));
      }
    }
    return out;
  }

  static bool _sameAttrs(Object? a, Object? b) =>
      jsonEncode(a ?? const {}) == jsonEncode(b ?? const {});

  // ---- Pre-passes ---------------------------------------------------------

  static final _fenceOpen = RegExp(r'^\s*(`{3,}|~{3,})');

  /// Drops `%%…%%` (Obsidian) and `<!-- … -->` comments outside code.
  List<String> _stripComments(List<String> lines) {
    final out = <String>[];
    String? fence;
    var inPercent = false;
    var inHtml = false;
    for (var line in lines) {
      line = line.trimRight();
      if (!inPercent && !inHtml) {
        final f = _fenceOpen.firstMatch(line);
        if (fence != null) {
          if (f != null &&
              f.group(1)![0] == fence[0] &&
              f.group(1)!.length >= fence.length &&
              line.trim() == f.group(1)) {
            fence = null;
          }
          out.add(line);
          continue;
        }
        if (f != null) {
          fence = f.group(1);
          out.add(line);
          continue;
        }
      }
      var s = line;
      final b = StringBuffer();
      var i = 0;
      while (i < s.length) {
        if (inPercent) {
          final e = s.indexOf('%%', i);
          if (e < 0) {
            i = s.length;
          } else {
            inPercent = false;
            i = e + 2;
          }
        } else if (inHtml) {
          final e = s.indexOf('-->', i);
          if (e < 0) {
            i = s.length;
          } else {
            inHtml = false;
            i = e + 3;
          }
        } else if (s.startsWith('%%', i)) {
          inPercent = true;
          i += 2;
        } else if (s.startsWith('<!--', i)) {
          inHtml = true;
          i += 4;
        } else {
          b.write(s[i++]);
        }
      }
      final r = b.toString();
      // A line that was only a comment disappears.
      if (r.trim().isEmpty && s.trim().isNotEmpty) continue;
      out.add(r);
    }
    return out;
  }

  static final _footnoteDef = RegExp(r'^\[\^([^\]\s]+)\]:\s?(.*)$');

  List<String> _takeFootnoteDefinitions(List<String> lines) {
    final out = <String>[];
    String? fence;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final f = _fenceOpen.firstMatch(line);
      if (fence != null) {
        if (f != null &&
            f.group(1)![0] == fence[0] &&
            f.group(1)!.length >= fence.length &&
            line.trim() == f.group(1)) {
          fence = null;
        }
        out.add(line);
        continue;
      }
      if (f != null) {
        fence = f.group(1);
        out.add(line);
        continue;
      }
      final m = _footnoteDef.firstMatch(line);
      if (m == null) {
        out.add(line);
        continue;
      }
      final parts = <String>[m.group(2)!];
      var j = i + 1;
      while (j < lines.length) {
        final l = lines[j];
        if (l.startsWith('    ') || l.startsWith('\t') || l.startsWith('  ')) {
          parts.add(l.trim());
          j++;
        } else if (l.trim().isEmpty &&
            j + 1 < lines.length &&
            (lines[j + 1].startsWith('    ') ||
                lines[j + 1].startsWith('\t'))) {
          j++;
        } else {
          break;
        }
      }
      i = j - 1;
      footnotes[m.group(1)!] = parts.join(' ');
    }
    // Definitions become inline text: plain, brackets balanced.
    for (final k in footnotes.keys.toList()) {
      footnotes[k] = _footnotePlain(footnotes[k]!);
    }
    return out;
  }

  String _footnotePlain(String md) {
    final saved = (List.of(attachments), unresolved, Set.of(tags));
    final runs = _InlineParser(
      this,
      const {},
      footnotesEnabled: false,
    ).parse(md);
    attachments
      ..clear()
      ..addAll(saved.$1);
    unresolved = saved.$2;
    tags
      ..clear()
      ..addAll(saved.$3);
    var s = runs
        .where((r) => r.kind == _RunKind.text)
        .map((r) => r.text)
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Brackets must balance for `^[…]`; otherwise drop them.
    var depth = 0;
    var ok = true;
    for (final c in s.split('')) {
      if (c == '[') depth++;
      if (c == ']') depth--;
      if (depth < 0) ok = false;
    }
    if (depth != 0) ok = false;
    if (!ok) s = s.replaceAll('[', '(').replaceAll(']', ')');
    return s;
  }

  // ---- Blocks -------------------------------------------------------------

  static final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$');
  static final _hr = RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$');
  static final _quote = RegExp(r'^\s{0,3}>');
  static final _listItem = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])(?:\s+(.*))?$');
  static final _taskBox = RegExp(r'^\[([ xX])\]\s+(.*)$');
  static final _tableDelimiter = RegExp(
    r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$',
  );
  static final _noteEmbedLine = RegExp(r'^!\[\[([^\]]+)\]\]$');

  List<_Line> _blocks(List<String> lines) {
    final out = <_Line>[];
    final listWidths = <int>[];

    int width(String indent) {
      var w = 0;
      for (final c in indent.split('')) {
        w += c == '\t' ? 4 : 1;
      }
      return w;
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Fenced code.
      final fence = _fenceOpen.firstMatch(line);
      if (fence != null) {
        final marker = fence.group(1)!;
        final code = <String>[];
        i++;
        while (i < lines.length) {
          final l = lines[i];
          final c = _fenceOpen.firstMatch(l);
          if (c != null &&
              c.group(1)![0] == marker[0] &&
              c.group(1)!.length >= marker.length &&
              l.trim() == c.group(1)) {
            i++;
            break;
          }
          code.add(l);
          i++;
        }
        // Remove the fence's own indentation from each line.
        final indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!.length;
        for (final l in code) {
          final text =
              l.length >= indent && l.substring(0, indent).trim().isEmpty
              ? l.substring(indent)
              : l.trimLeft();
          out.add(
            _Line([
              if (text.isNotEmpty) {'insert': text},
              {
                'insert': '\n',
                'attributes': {'code-block': true},
              },
            ]),
          );
        }
        listWidths.clear();
        continue;
      }

      // Display maths over several lines.
      if (trimmed.startsWith(r'$$') &&
          !(trimmed.length >= 5 && trimmed.endsWith(r'$$'))) {
        var k = i;
        final parts = <String>[];
        var closed = false;
        while (k < lines.length && k < i + 200) {
          final t = lines[k].trim();
          parts.add(t);
          if (k > i && t.endsWith(r'$$')) {
            closed = true;
            break;
          }
          if (k == i && t.length > 2 && t.endsWith(r'$$')) {
            closed = true;
            break;
          }
          k++;
        }
        if (closed) {
          var latex = parts.join(' ').trim();
          latex = latex.substring(2, latex.length - 2).trim();
          if (latex.isNotEmpty) {
            out.add(_paragraphLine([_Run.text(displayMathMarker(latex))], {}));
            i = k + 1;
            listWidths.clear();
            continue;
          }
        }
      }

      // Table.
      if (line.contains('|') &&
          i + 1 < lines.length &&
          lines[i + 1].contains('-') &&
          _tableDelimiter.hasMatch(lines[i + 1]) &&
          _splitRow(lines[i + 1]).isNotEmpty) {
        final rows = <List<String>>[_splitRow(line)];
        var k = i + 2;
        while (k < lines.length &&
            lines[k].trim().isNotEmpty &&
            lines[k].contains('|')) {
          rows.add(_splitRow(lines[k]));
          k++;
        }
        i = k;
        out.add(_tableLine(rows));
        listWidths.clear();
        continue;
      }

      if (_hr.hasMatch(line)) {
        i++;
        continue;
      }

      final h = _heading.firstMatch(line);
      if (h != null) {
        final level = h.group(1)!.length;
        final header = level == 1 ? 1 : (level - 1).clamp(1, 3);
        final runs = _InlineParser(this, const {}).parse(h.group(2)!);
        out.add(
          _paragraphLine(runs, {'header': header}, header: _plainOf(runs)),
        );
        i++;
        listWidths.clear();
        continue;
      }

      // Embedded note on a line of its own.
      final embed = _noteEmbedLine.firstMatch(trimmed);
      if (embed != null) {
        final link = _noteEmbedLink(embed.group(1)!);
        if (link != null) {
          out.add(
            _Line([
              {
                'insert': {noteEmbedType: noteEmbedData(link)},
              },
              {'insert': '\n'},
            ], isEmbed: true),
          );
          i++;
          listWidths.clear();
          continue;
        }
      }

      if (_quote.hasMatch(line)) {
        final text = line.replaceFirst(RegExp(r'^\s*(?:>\s?)+'), '');
        final runs = _InlineParser(this, const {}).parse(text);
        out.add(_paragraphLine(runs, {'blockquote': true}));
        i++;
        listWidths.clear();
        continue;
      }

      final li = _listItem.firstMatch(line);
      if (li != null) {
        final w = width(li.group(1)!);
        while (listWidths.isNotEmpty && listWidths.last > w) {
          listWidths.removeLast();
        }
        if (listWidths.isEmpty || listWidths.last < w) listWidths.add(w);
        final indent = listWidths.length - 1;
        var text = li.group(3) ?? '';
        final ordered = RegExp(r'^\d').hasMatch(li.group(2)!);
        String kind = ordered ? 'ordered' : 'bullet';
        final task = _taskBox.firstMatch(text);
        if (task != null && !ordered) {
          kind = task.group(1) == ' ' ? 'unchecked' : 'checked';
          text = task.group(2)!;
        } else if (task != null) {
          kind = task.group(1) == ' ' ? 'unchecked' : 'checked';
          text = task.group(2)!;
        } else if (RegExp(r'^\[([ xX])\]$').hasMatch(text.trim())) {
          kind = text.trim()[1] == ' ' ? 'unchecked' : 'checked';
          text = '';
        }
        final runs = _InlineParser(this, const {}).parse(text);
        out.add(
          _paragraphLine(runs, {
            'list': kind,
            if (indent > 0) 'indent': indent,
          }),
        );
        i++;
        continue;
      }

      // A plain paragraph (indentation dropped).
      final runs = _InlineParser(this, const {}).parse(trimmed);
      out.add(_paragraphLine(runs, {}));
      listWidths.clear();
      i++;
    }
    return out;
  }

  String? _noteEmbedLink(String inner) {
    final parsed = _WikiTarget.parse(inner);
    if (parsed == null) return null;
    final ref = parsed.target.isEmpty
        ? (selfId == null ? null : MdNoteRef(selfId!, title))
        : resolver.note(parsed.target);
    if (ref == null) return null;
    return noteLink(ref.id, heading: parsed.heading, block: parsed.block);
  }

  _Line _paragraphLine(List<_Run> runs, _Attrs block, {String? header}) {
    // A line holding only attachments is dropped (they became attachments).
    final onlyAttach =
        runs.any((r) => r.kind == _RunKind.attach || r.kind == _RunKind.drop) &&
        runs.every(
          (r) =>
              r.kind == _RunKind.attach ||
              r.kind == _RunKind.drop ||
              (r.kind == _RunKind.text && r.text.trim().isEmpty),
        );
    if (onlyAttach) return _Line(const []);

    final ops = <_Attrs>[];
    for (final r in runs) {
      switch (r.kind) {
        case _RunKind.drop:
          break;
        case _RunKind.attach:
        case _RunKind.text:
          if (r.text.isEmpty) break;
          final parts = r.text.split('\n');
          for (var k = 0; k < parts.length; k++) {
            if (parts[k].isNotEmpty) {
              ops.add({
                'insert': parts[k],
                if (r.attrs.isNotEmpty) 'attributes': r.attrs,
              });
            }
            if (k < parts.length - 1) ops.add({'insert': '\n'});
          }
      }
    }
    ops.add({'insert': '\n', if (block.isNotEmpty) 'attributes': block});
    return _Line(ops, header: header);
  }

  String _plainOf(List<_Run> runs) =>
      runs.where((r) => r.kind == _RunKind.text).map((r) => r.text).join();

  // ---- Tables -------------------------------------------------------------

  /// Splits a table row on unescaped `|` (not inside backticks), without the
  /// outer pipes.
  List<String> _splitRow(String row) {
    var s = row.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
    final cells = <String>[];
    final cur = StringBuffer();
    var inCode = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length && s[i + 1] == '|') {
        cur.write('|');
        i++;
      } else if (c == '`') {
        inCode = !inCode;
        cur.write(c);
      } else if (c == '|' && !inCode) {
        cells.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    cells.add(cur.toString());
    return cells.map((c) => c.trim()).toList();
  }

  _Line _tableLine(List<List<String>> rows) {
    String cell(String md) {
      final runs = _InlineParser(
        this,
        const {},
        brAsNewline: true,
      ).parse(md.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'));
      return _plainOf(runs).trim();
    }

    var parsed = [
      for (final r in rows) [for (final c in r) cell(c)],
    ];
    var header = true;
    if (parsed.isNotEmpty && parsed.first.every((c) => c.isEmpty)) {
      // An all-empty header is how a header-less table is written.
      if (parsed.length > 1) {
        parsed = parsed.sublist(1);
        header = false;
      }
    }
    final table = NoteTable(rows: parsed, header: header);
    return _Line([
      {
        'insert': {tableEmbedType: table.encode()},
      },
      {'insert': '\n'},
    ], isEmbed: true);
  }
}

// ---- Wiki link targets --------------------------------------------------------

class _WikiTarget {
  _WikiTarget(this.target, this.heading, this.block, this.alias);
  final String target;
  final String? heading;
  final String? block;
  final String? alias;

  /// `Note#Heading|alias`, `Note#^block`, `#Heading`, `Note`.
  static _WikiTarget? parse(String inner) {
    if (inner.contains('\n')) return null;
    final bar = inner.indexOf('|');
    final head = bar < 0 ? inner : inner.substring(0, bar);
    final alias = bar < 0 ? null : inner.substring(bar + 1).trim();
    final hash = head.indexOf('#');
    var target = (hash < 0 ? head : head.substring(0, hash)).trim();
    String? heading;
    String? block;
    if (hash >= 0) {
      var frag = head.substring(hash + 1).trim();
      // `Note#H1#H2`: the last segment is the heading.
      final nested = frag.lastIndexOf('#');
      if (nested >= 0 && !frag.startsWith('^')) {
        frag = frag.substring(nested + 1).trim();
      }
      if (frag.startsWith('^')) {
        final id = frag.substring(1);
        if (blockIdChars.hasMatch(id)) block = id;
      } else if (frag.isNotEmpty) {
        heading = frag;
      }
    }
    target = target.replaceAll('\\', '/');
    return _WikiTarget(
      target,
      heading,
      block,
      alias == null || alias.isEmpty ? null : alias,
    );
  }
}

// ---- Inline -------------------------------------------------------------------

bool _isPunct(String c) => r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~'''.contains(c);
bool _isSpace(String c) => c.trim().isEmpty;
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
bool _isWord(String c) => _wordChar.hasMatch(c);

final _tagPattern = RegExp(
  r'#([\p{L}\p{N}_\-/]*[\p{L}_\-/][\p{L}\p{N}_\-/]*)',
  unicode: true,
);
final _extension = RegExp(r'\.[A-Za-z0-9]{1,5}$');

class _InlineParser {
  _InlineParser(
    this.c,
    this.baseAttrs, {
    this.footnotesEnabled = true,
    this.brAsNewline = false,
  });

  final _Converter c;
  final _Attrs baseAttrs;
  final bool footnotesEnabled;
  final bool brAsNewline;

  late String s;
  Map<int, int> _math = {};

  List<_Run> parse(String input) {
    s = input;
    _math = {for (final m in findInlineMath(s)) m.start: m.end};
    return _parseRange(0, s.length, baseAttrs);
  }

  /// Parses `s[from, to)` with [attrs] applied.
  List<_Run> _parseRange(int from, int to, _Attrs attrs) {
    final runs = <_Run>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      runs.add(_Run.text(buf.toString(), attrs));
      buf.clear();
    }

    var i = from;
    while (i < to) {
      final ch = s[i];

      if (ch == r'\' && i + 1 < to && _isPunct(s[i + 1])) {
        buf.write(s[i + 1]);
        i += 2;
        continue;
      }

      if (ch == '`') {
        var n = 1;
        while (i + n < to && s[i + n] == '`') {
          n++;
        }
        final fence = '`' * n;
        var close = -1;
        var j = i + n;
        while (j < to) {
          final k = s.indexOf(fence, j);
          if (k < 0 || k >= to) break;
          var e = k + n;
          if (e < to && s[e] == '`') {
            while (e < to && s[e] == '`') {
              e++;
            }
            j = e;
            continue;
          }
          close = k;
          break;
        }
        if (close >= 0) {
          flush();
          var code = s.substring(i + n, close);
          if (code.length > 1 && code.startsWith(' ') && code.endsWith(' ')) {
            code = code.substring(1, code.length - 1);
          }
          runs.add(_Run.text(code, {...attrs, 'code': true}));
          i = close + n;
        } else {
          buf.write(fence);
          i += n;
        }
        continue;
      }

      if (ch == r'$') {
        final end = _math[i];
        if (end != null && end <= to) {
          buf.write(s.substring(i, end));
          i = end;
          continue;
        }
      }

      if (ch == '!' && s.startsWith('![[', i)) {
        final end = s.indexOf(']]', i + 3);
        if (end >= 0 && end < to && !s.substring(i + 3, end).contains('\n')) {
          flush();
          runs.addAll(_embed(s.substring(i + 3, end), attrs));
          i = end + 2;
          continue;
        }
      }

      if (ch == '[' && s.startsWith('[[', i)) {
        final end = s.indexOf(']]', i + 2);
        if (end >= 0 && end < to && !s.substring(i + 2, end).contains('\n')) {
          flush();
          i = _wikiLink(runs, s.substring(i + 2, end), attrs, end + 2, to);
          continue;
        }
      }

      if (ch == '!' && i + 1 < to && s[i + 1] == '[') {
        final r = _markdownLink(i + 1, to, attrs, image: true);
        if (r != null) {
          flush();
          runs.addAll(r.runs);
          i = r.end;
          continue;
        }
      }

      if (ch == '[') {
        if (s.startsWith('[@', i)) {
          final end = _closingBracket(i, to);
          if (end > 0) {
            buf.write(s.substring(i, end + 1));
            i = end + 1;
            continue;
          }
        }
        if (s.startsWith('[^', i)) {
          final end = s.indexOf(']', i);
          if (end > 0 && end < to) {
            final name = s.substring(i + 2, end);
            final text = footnotesEnabled ? c.footnotes[name] : null;
            if (text != null && text.isNotEmpty) {
              buf.write('^[$text]');
              i = end + 1;
              continue;
            }
            if (name.contains(' ') || name.isEmpty) {
              // Not a footnote reference.
            }
          }
        }
        final r = _markdownLink(i, to, attrs, image: false);
        if (r != null) {
          flush();
          runs.addAll(r.runs);
          i = r.end;
          continue;
        }
      }

      if (ch == '^' && i + 1 < to && s[i + 1] == '[') {
        final end = _closingBracket(i + 1, to);
        if (end > 0) {
          // Raw, but citations Corplex's export turned into wiki links
          // come back as `[@key]`.
          buf.write(
            s
                .substring(i, end + 1)
                .replaceAllMapped(
                  RegExp(r'\[\[@[^\]|]*\|(@[A-Za-z0-9_:.\-]+)\]\]'),
                  (m) => '[${m[1]}]',
                ),
          );
          i = end + 1;
          continue;
        }
      }

      if (ch == '<') {
        final br = RegExp(
          r'^<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(s.substring(i, to));
        if (br != null) {
          buf.write('\n');
          i += br.group(0)!.length;
          continue;
        }
        final auto = RegExp(r'^<((?:https?|mailto|ftp):[^\s<>]+)>')
            .firstMatch(s.substring(i, to));
        if (auto != null) {
          flush();
          runs.add(
            _Run.text(auto.group(1)!, {...attrs, 'link': auto.group(1)}),
          );
          i += auto.group(0)!.length;
          continue;
        }
      }

      if (ch == '*' || ch == '_' || ch == '~' || ch == '=') {
        final done = _emphasis(i, to, attrs, runs, flush);
        if (done > 0) {
          i = done;
          continue;
        }
      }

      if (ch == '#' && (i == 0 || _isSpace(s[i - 1]) || s[i - 1] == '(')) {
        final m = _tagPattern.matchAsPrefix(s.substring(i, to));
        if (m != null) {
          c.tags.add(m.group(1)!);
          buf.write(m.group(0));
          i += m.group(0)!.length;
          continue;
        }
      }

      buf.write(ch);
      i++;
    }
    flush();
    return runs;
  }

  /// Index of the `]` closing the `[` at [open], honouring nesting, or -1.
  int _closingBracket(int open, int to) {
    var depth = 0;
    for (var i = open; i < to; i++) {
      final ch = s[i];
      if (ch == r'\') {
        i++;
      } else if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  // ---- Emphasis ----

  /// Handles `**`, `__`, `*`, `_`, `~~`, `==` at [i]. Returns the index
  /// after the construct, or 0 when it isn't one (the character is text).
  int _emphasis(
    int i,
    int to,
    _Attrs attrs,
    List<_Run> runs,
    void Function() flush,
  ) {
    final ch = s[i];
    String delim;
    Map<String, Object?> add;
    if (ch == '*' || ch == '_') {
      if (s.startsWith(ch * 3, i)) {
        delim = ch * 3;
        add = {'bold': true, 'italic': true};
      } else if (s.startsWith(ch * 2, i)) {
        delim = ch * 2;
        add = {'bold': true};
      } else {
        delim = ch;
        add = {'italic': true};
      }
    } else if (ch == '~') {
      if (!s.startsWith('~~', i)) return 0;
      delim = '~~';
      add = {'strike': true};
    } else {
      if (!s.startsWith('==', i)) return 0;
      delim = '==';
      add = {'background': NoteHighlight.yellow.hex};
    }
    final inner = i + delim.length;
    if (inner >= to || _isSpace(s[inner])) return 0;
    if (ch == '_' && i > 0 && _isWord(s[i - 1])) return 0;
    final close = _findCloser(delim, inner, to);
    if (close < 0) {
      // `***a** b*`-style mixes aren't supported: try a shorter marker.
      if (delim.length == 3) {
        final shorter = ch * 2;
        final c2 = _findCloser(shorter, i + 2, to);
        if (c2 >= 0) {
          flush();
          runs.addAll(_parseRange(i + 2, c2, {...attrs, 'bold': true}));
          return c2 + 2;
        }
      }
      return 0;
    }
    flush();
    runs.addAll(_parseRange(inner, close, {...attrs, ...add}));
    return close + delim.length;
  }

  int _findCloser(String delim, int from, int to) {
    final ch = delim[0];
    var i = from;
    while (i < to) {
      final x = s[i];
      if (x == r'\') {
        i += 2;
        continue;
      }
      if (x == '`') {
        var n = 1;
        while (i + n < to && s[i + n] == '`') {
          n++;
        }
        final k = s.indexOf('`' * n, i + n);
        i = k >= 0 && k < to ? k + n : i + n;
        continue;
      }
      if (x == r'$' && _math[i] != null) {
        i = _math[i]!;
        continue;
      }
      if (x == '[' && s.startsWith('[[', i)) {
        final e = s.indexOf(']]', i);
        if (e >= 0 && e < to) {
          i = e + 2;
          continue;
        }
      }
      if (x == ch && s.startsWith(delim, i) && i > from) {
        var run = 0;
        while (i + run < to && s[i + run] == ch) {
          run++;
        }
        final prevOk = !_isSpace(s[i - 1]);
        if (run == delim.length ||
            (run > delim.length && ch != '*' && ch != '_')) {
          final after = i + delim.length;
          final afterOk = ch != '_' || after >= to || !_isWord(s[after]);
          if (prevOk && afterOk) return i;
        } else if (run > delim.length && (ch == '*' || ch == '_')) {
          // A longer run: its first part may close ours when it ends a
          // nested construct (`**a *b***`): take the last `delim` of it.
          final pos = i + run - delim.length;
          if (!_isSpace(s[pos - 1]) &&
              (ch != '_' ||
                  pos + delim.length >= to ||
                  !_isWord(s[pos + delim.length]))) {
            return pos;
          }
        }
        i += run;
        continue;
      }
      i++;
    }
    return -1;
  }

  // ---- Links ----

  List<_Run> _embed(String inner, _Attrs attrs) {
    final t = _WikiTarget.parse(inner);
    if (t == null) return [_Run.text('![[$inner]]', attrs)];
    final noteRef = t.target.isEmpty
        ? (c.selfId == null ? null : MdNoteRef(c.selfId!, c.title))
        : c.resolver.note(t.target);
    final isFileName =
        _extension.hasMatch(t.target) &&
        !t.target.toLowerCase().endsWith('.md');
    if (noteRef != null && !(isFileName && c.resolver.file(t.target) != null)) {
      final link = noteLink(noteRef.id, heading: t.heading, block: t.block);
      // On its own line the block parser makes a card; mid-text it reads as
      // a link to the note.
      return [
        _Run.text(_linkText(noteRef, t, null), {...attrs, 'link': link}),
      ];
    }
    final file = t.target.isEmpty ? null : c.resolver.file(t.target);
    if (file != null) {
      _addAttachment(file);
      return [_Run.drop()];
    }
    c.unresolved++;
    return [_Run.text(t.alias ?? t.target, attrs)];
  }

  void _addAttachment(String path) {
    if (!c.attachments.contains(path)) c.attachments.add(path);
  }

  String _linkText(MdNoteRef ref, _WikiTarget t, String? alias) {
    if (alias != null && alias.isNotEmpty) return alias;
    if (t.heading != null) return '${ref.title} › ${t.heading}';
    if (t.block != null) {
      final preview = c.resolver.blockPreview(ref.id, t.block!);
      if (preview != null && preview.isNotEmpty) {
        return '${ref.title} › $preview';
      }
    }
    return ref.title;
  }

  /// Handles the inside of `[[…]]`; returns the index after it.
  int _wikiLink(
    List<_Run> runs,
    String inner,
    _Attrs attrs,
    int after,
    int to,
  ) {
    final t = _WikiTarget.parse(inner);
    if (t == null) {
      runs.add(_Run.text('[[$inner]]', attrs));
      return after;
    }
    final bareAlias = t.alias;

    // Corplex's own vault writes a citation as `[[@key Title|@key]]`.
    final base = t.target.split('/').last;
    if (base.startsWith('@') &&
        bareAlias != null &&
        RegExp(r'^@[A-Za-z0-9_:.\-]+$').hasMatch(bareAlias)) {
      var key = '[$bareAlias';
      var end = after;
      final loc = RegExp(
        r'^,\s*((?:pp?\.|chap\.)\s*[0-9A-Za-z–\-]+(?:,\s*[0-9–\-]+)*)',
      ).firstMatch(s.substring(after, to));
      if (loc != null) {
        key += ', ${loc.group(1)}';
        end += loc.group(0)!.length;
      }
      runs.add(_Run.text('$key]', attrs));
      return end;
    }

    final noteRef = t.target.isEmpty
        ? (c.selfId == null ? null : MdNoteRef(c.selfId!, c.title))
        : c.resolver.note(t.target);
    final isFileName =
        _extension.hasMatch(t.target) &&
        !t.target.toLowerCase().endsWith('.md');
    if (isFileName && c.resolver.file(t.target) != null) {
      _addAttachment(c.resolver.file(t.target)!);
      runs.add(_Run.attach(bareAlias ?? base));
      return after;
    }
    if (noteRef != null) {
      final link = noteLink(noteRef.id, heading: t.heading, block: t.block);
      runs.add(
        _Run.text(_linkText(noteRef, t, bareAlias), {...attrs, 'link': link}),
      );
      return after;
    }
    if (t.target.isNotEmpty) {
      final file = c.resolver.file(t.target);
      if (file != null) {
        _addAttachment(file);
        runs.add(_Run.attach(bareAlias ?? base));
        return after;
      }
    }
    c.unresolved++;
    final shown =
        bareAlias ??
        (t.target.isEmpty
            ? (t.heading ?? (t.block == null ? '' : '^${t.block}'))
            : t.heading != null
            ? '${t.target} › ${t.heading}'
            : t.block != null
            ? t.target
            : t.target);
    runs.add(_Run.text(shown, attrs));
    return after;
  }

  /// `[text](url)` / `![alt](url)` starting at the `[` at [open].
  ({List<_Run> runs, int end})? _markdownLink(
    int open,
    int to,
    _Attrs attrs, {
    required bool image,
  }) {
    final close = _closingBracket(open, to);
    if (close < 0 || close + 1 >= to || s[close + 1] != '(') return null;
    // The destination: up to the matching ')' (parentheses may nest).
    var depth = 0;
    var end = -1;
    for (var i = close + 1; i < to; i++) {
      final ch = s[i];
      if (ch == r'\') {
        i++;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return null;
    final text = s.substring(open + 1, close);
    var dest = s.substring(close + 2, end).trim();
    // Optional title: `url "title"`.
    final withTitle = RegExp(r'''^(.*?)\s+("[^"]*"|'[^']*')$''')
        .firstMatch(dest);
    if (withTitle != null && !dest.startsWith('<')) dest = withTitle.group(1)!;
    if (dest.startsWith('<') && dest.contains('>')) {
      dest = dest.substring(1, dest.indexOf('>'));
    }
    final after = end + 1;

    final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):').firstMatch(dest);
    final isWindowsPath = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(dest);

    if (image) {
      if (dest.startsWith('data:')) return (runs: [_Run.drop()], end: after);
      if (scheme != null && !isWindowsPath) {
        if (dest.startsWith(_webScheme)) {
          final label = text.trim().isEmpty ? dest : text.trim();
          return (
            runs: [
              _Run.text(label, {...attrs, 'link': dest}),
            ],
            end: after,
          );
        }
        return (runs: [_Run.text(text, attrs)], end: after);
      }
      final path = _decode(dest).split('#').first;
      final file = c.resolver.file(path);
      if (file != null) {
        _addAttachment(file);
        return (runs: [_Run.drop()], end: after);
      }
      c.unresolved++;
      return (runs: [_Run.text(text, attrs)], end: after);
    }

    // Plain link.
    if (scheme != null && !isWindowsPath) {
      final lower = scheme.group(1)!.toLowerCase();
      if (const {'http', 'https', 'mailto', 'tel', 'ftp'}.contains(lower)) {
        final inner = _InlineParser(c, {
          ...attrs,
          'link': dest,
        }, footnotesEnabled: footnotesEnabled);
        inner.s = text;
        inner._math = {for (final m in findInlineMath(text)) m.start: m.end};
        final r = inner._parseRange(0, text.length, {...attrs, 'link': dest});
        return (
          runs: r.isEmpty
              ? [
                  _Run.text(dest, {...attrs, 'link': dest}),
                ]
              : r,
          end: after,
        );
      }
      return (runs: _parseSub(text, attrs), end: after);
    }

    final decoded = _decode(dest);
    final hash = decoded.indexOf('#');
    final path = hash < 0 ? decoded : decoded.substring(0, hash);
    final fragment = hash < 0 ? '' : decoded.substring(hash + 1);
    final isNote = path.isEmpty || path.toLowerCase().endsWith('.md');
    if (isNote) {
      MdNoteRef? ref = path.isEmpty
          ? (c.selfId == null ? null : MdNoteRef(c.selfId!, c.title))
          : c.resolver.note(path);
      if (ref != null) {
        String? heading;
        String? block;
        if (fragment.startsWith('^') &&
            blockIdChars.hasMatch(fragment.substring(1))) {
          block = fragment.substring(1);
        } else if (fragment.isNotEmpty) {
          heading = fragment;
        }
        final link = noteLink(ref.id, heading: heading, block: block);
        final t = _WikiTarget(
          path,
          heading,
          block,
          text.trim().isEmpty ? null : text.trim(),
        );
        return (
          runs: [
            _Run.text(_linkText(ref, t, t.alias), {...attrs, 'link': link}),
          ],
          end: after,
        );
      }
      c.unresolved++;
      return (runs: _parseSub(text, attrs), end: after);
    }
    final file = c.resolver.file(path);
    if (file != null) {
      _addAttachment(file);
      return (
        runs: [_Run.attach(text.isEmpty ? path.split('/').last : text)],
        end: after,
      );
    }
    c.unresolved++;
    return (runs: _parseSub(text, attrs), end: after);
  }

  List<_Run> _parseSub(String text, _Attrs attrs) {
    final p = _InlineParser(c, attrs, footnotesEnabled: footnotesEnabled);
    p.s = text;
    p._math = {for (final m in findInlineMath(text)) m.start: m.end};
    return p._parseRange(0, text.length, attrs);
  }

  static String _decode(String s) {
    try {
      return Uri.decodeFull(s);
    } on FormatException {
      return s;
    }
  }
}

/// A web link (http or https), kept as a link rather than resolved as a file.
final _webScheme = RegExp(r'https?://', caseSensitive: false);
