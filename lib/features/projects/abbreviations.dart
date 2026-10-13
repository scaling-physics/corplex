import 'dart:math' as math;

import 'package:drift/drift.dart' show innerJoin;
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../export/export_model.dart';
import '../notes/editor_document.dart';
import 'chapters.dart' show ProjectNoteRow, compareChapterRows;

/// Abbreviations in a thesis, found in the writing itself.
///
/// The convention is to spell an abbreviation out where a chapter first uses
/// it, "medial prefrontal cortex (mPFC)". Definitions are detected with the
/// Schwartz & Hearst (2003) algorithm, so the writer adds no syntax and
/// nothing is stored; the report is derived from the notes every time.

/// A definition found in text: [sf] (the short form) spelled out as
/// [longForm].
class AbbreviationDefinition {
  const AbbreviationDefinition({
    required this.sf,
    required this.longForm,
    required this.offset,
  });

  final String sf;
  final String longForm;

  /// Where the short form starts in the text it was found in (the one inside
  /// the parentheses, or the one before them).
  final int offset;

  @override
  String toString() => 'Definition($sf = "$longForm" @$offset)';
}

/// Short forms are 2-10 characters without spaces, with a letter, and either
/// two or more capitals or a capital and a digit ("mPFC", "CA1", "5-HT").
bool isShortForm(String s) {
  if (s.length < 2 || s.length > 10) return false;
  if (!_sfChars.hasMatch(s)) return false;
  final upper = RegExp(r'\p{Lu}', unicode: true).allMatches(s).length;
  final hasDigit = RegExp(r'\p{N}', unicode: true).hasMatch(s);
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(s)) return false;
  return upper >= 2 || (upper >= 1 && hasDigit);
}

final _sfChars = RegExp(r'^[\p{L}\p{N}][\p{L}\p{N}\-+/]*$', unicode: true);

final _maskPatterns = [
  RegExp(r'\[@[^\]\n]*\]'), // citations, [@?] too
  RegExp(r'\{[#@]fig:[^}\n]*\}', caseSensitive: false), // figure markers
  RegExp(r'\{[#@]tbl:[^}\n]*\}', caseSensitive: false),
  RegExp(r'\$\$.*?\$\$'), // maths that is still source
  RegExp(r'\$[^$\n]+\$'),
  RegExp(r'(?:https?://|www\.|corplex://)\S+'),
];

/// [plain] with everything abbreviations must not be read from (citations,
/// figure markers, maths, URLs, embed placeholders) blanked out. Same length,
/// so offsets stay the editor's.
String _mask(String plain) {
  var out = plain.replaceAll('￼', ' ');
  for (final p in _maskPatterns) {
    out = out.replaceAllMapped(p, (m) => ' ' * (m.end - m.start));
  }
  return out;
}

/// Matches [sf] against [lf] right to left (Schwartz & Hearst): every short
/// form character must appear in order, the first at the start of a word.
/// Returns the long form from the word holding the first match, or null.
String? _bestLongForm(String sf, String lf) {
  bool alnum(String c) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);
  var s = sf.length - 1;
  var l = lf.length - 1;
  while (s >= 0) {
    final c = sf[s].toLowerCase();
    if (!alnum(c)) {
      s--;
      continue;
    }
    while ((l >= 0 && lf[l].toLowerCase() != c) ||
        (s == 0 && l > 0 && alnum(lf[l - 1]))) {
      l--;
    }
    if (l < 0) return null;
    l--;
    s--;
  }
  final start = lf.lastIndexOf(' ', math.max(l, 0)) + 1;
  return lf.substring(l < 0 ? 0 : start);
}

String? _longFormBefore(String before, String sf) {
  // Stay inside the sentence and out of other parentheses.
  var cut = 0;
  for (var i = 0; i < before.length; i++) {
    final c = before[i];
    if (';:()'.contains(c) ||
        ('.!?'.contains(c) &&
            (i + 1 >= before.length || before[i + 1] == ' '))) {
      cut = i + 1;
    }
  }
  final words = before
      .substring(cut)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final maxWords = math.min(sf.length + 5, sf.length * 2);
  final tail = words.length > maxWords
      ? words.sublist(words.length - maxWords)
      : words;
  if (tail.isEmpty) return null;
  final lf = _bestLongForm(sf, tail.join(' '));
  return _cleanLongForm(lf, sf);
}

String? _cleanLongForm(String? lf, String sf) {
  if (lf == null) return null;
  final t = lf.replaceAll(RegExp(r'[,\s]+$'), '').trim();
  if (t.length <= sf.length) return null;
  if (t.toLowerCase() == sf.toLowerCase()) return null;
  // "(i.e. the mPFC)" must not define mPFC as itself.
  if (t.split(RegExp(r'[\s\-]+')).contains(sf)) return null;
  return t;
}

/// The definitions in [plain] (text as the editor shows it), in order.
/// Offsets are positions in [plain].
List<AbbreviationDefinition> findAbbreviationDefinitions(String plain) {
  final masked = _mask(plain);
  final out = <AbbreviationDefinition>[];
  var pos = 0;
  for (final line in masked.split('\n')) {
    _scanLine(line, pos, out);
    pos += line.length + 1;
  }
  return out;
}

void _scanLine(String line, int base, List<AbbreviationDefinition> out) {
  for (var i = 0; i < line.length; i++) {
    if (line[i] != '(') continue;
    var depth = 0;
    var j = -1;
    for (var k = i; k < line.length; k++) {
      if (line[k] == '(') depth++;
      if (line[k] == ')' && --depth == 0) {
        j = k;
        break;
      }
    }
    if (j < 0) continue;
    final inner = line.substring(i + 1, j);
    final trimmed = inner.trim();
    if (trimmed.isEmpty) continue;
    final innerStart = i + 1 + (inner.length - inner.trimLeft().length);

    // "long form (SF)", also with a plural SF: "receptors (NMDARs)".
    var sf = trimmed;
    if (sf.endsWith('s') &&
        isShortForm(sf.substring(0, sf.length - 1)) &&
        RegExp(r'\p{Lu}$', unicode: true).hasMatch(sf[sf.length - 2])) {
      sf = sf.substring(0, sf.length - 1);
    }
    if (isShortForm(sf)) {
      final lf = _longFormBefore(line.substring(0, i), sf);
      if (lf != null) {
        out.add(
          AbbreviationDefinition(
            sf: sf,
            longForm: lf,
            offset: base + innerStart,
          ),
        );
      }
      continue;
    }

    // "SF (long form)": the parenthesised part is longer than the token.
    if (trimmed.contains(' ') || trimmed.contains('-')) {
      final m = RegExp(r'(\S+)\s*$').firstMatch(line.substring(0, i));
      if (m == null) continue;
      final token = m.group(1)!;
      if (!isShortForm(token) || trimmed.length <= token.length) continue;
      final words = trimmed.split(RegExp(r'\s+')).length;
      if (words > math.min(token.length + 5, token.length * 2)) continue;
      final lf = _cleanLongForm(_bestLongForm(token, trimmed), token);
      if (lf != null && lf == trimmed) {
        out.add(
          AbbreviationDefinition(
            sf: token,
            longForm: lf,
            offset: base + m.start,
          ),
        );
      }
    }
  }
}

/// A note to analyse, as stored.
class AbbreviationSource {
  const AbbreviationSource({
    required this.noteId,
    required this.title,
    required this.content,
  });
  final String noteId;
  final String title;
  final String content;
}

/// An abbreviation the project spells out somewhere.
class DefinedAbbreviation {
  const DefinedAbbreviation({
    required this.sf,
    required this.longForm,
    required this.noteId,
    required this.title,
  });
  final String sf;
  final String longForm;

  /// The chapter whose definition gave [longForm].
  final String noteId;
  final String title;
}

/// A use of [sf] in a chapter before (or without) spelling it out there.
class AbbreviationIssue {
  const AbbreviationIssue({
    required this.sf,
    required this.offset,
    required this.length,
  });
  final String sf;

  /// In the editor's offsets.
  final int offset;
  final int length;

  String get message => "$sf is used before it's spelled out";

  TextSelection get selection =>
      TextSelection(baseOffset: offset, extentOffset: offset + length);
}

class ChapterAbbreviationIssues {
  const ChapterAbbreviationIssues({
    required this.noteId,
    required this.title,
    required this.issues,
  });
  final String noteId;
  final String title;
  final List<AbbreviationIssue> issues;
}

/// An abbreviation-like token used but never spelled out in the project.
class UndefinedAbbreviation {
  const UndefinedAbbreviation({
    required this.token,
    required this.count,
    required this.noteId,
    required this.title,
    required this.offset,
  });
  final String token;
  final int count;

  /// First occurrence.
  final String noteId;
  final String title;
  final int offset;

  TextSelection get selection =>
      TextSelection(baseOffset: offset, extentOffset: offset + token.length);
}

class AbbreviationReport {
  const AbbreviationReport({
    this.defined = const [],
    this.chapters = const [],
    this.undefined = const [],
  });

  /// Alphabetical (case-insensitive) by short form.
  final List<DefinedAbbreviation> defined;

  /// Chapters with at least one issue, in chapter order.
  final List<ChapterAbbreviationIssues> chapters;

  /// Most used first.
  final List<UndefinedAbbreviation> undefined;

  int get issueCount => chapters.fold(0, (a, c) => a + c.issues.length);

  /// Nothing to show: no definitions and no issues.
  bool get isEmpty => defined.isEmpty && chapters.isEmpty;
}

final _roman = RegExp(r'^X{0,3}(IX|IV|V?I{0,3})$');
final _undefinedShape = RegExp(r'^[a-z]{0,2}[A-Z0-9]+(?:-[A-Z0-9]+)*s?$');
final _panel = RegExp(r'^\d+[A-Za-z]$');
final _tokenRe = RegExp(
  r'(?<![\p{L}\p{N}_])[\p{L}\p{N}]+(?:-[\p{L}\p{N}]+)*(?![\p{L}\p{N}_])',
  unicode: true,
);

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Analyses [chapters] (in chapter order).
AbbreviationReport analyzeAbbreviations(List<AbbreviationSource> chapters) {
  final plains = [
    for (final c in chapters) editorDocument(c.content).toPlainText(),
  ];
  final defs = [for (final p in plains) findAbbreviationDefinitions(p)];

  // Long form per short form: the most common (one vote per chapter, the
  // chapter's first definition), ties to the earliest.
  final votes = <String, List<(int, String)>>{};
  for (var i = 0; i < chapters.length; i++) {
    final seen = <String>{};
    for (final d in defs[i]) {
      if (seen.add(d.sf)) (votes[d.sf] ??= []).add((i, d.longForm));
    }
  }
  final defined = <DefinedAbbreviation>[];
  for (final e in votes.entries) {
    final counts = <String, int>{};
    for (final v in e.value) {
      counts.update(_norm(v.$2), (n) => n + 1, ifAbsent: () => 1);
    }
    final best = e.value.reduce(
      (a, b) => counts[_norm(b.$2)]! > counts[_norm(a.$2)]! ? b : a,
    );
    defined.add(
      DefinedAbbreviation(
        sf: e.key,
        longForm: best.$2,
        noteId: chapters[best.$1].noteId,
        title: chapters[best.$1].title,
      ),
    );
  }
  defined.sort((a, b) => _bySf(a.sf, b.sf));

  final known = votes.keys.toSet();
  final useRes = {
    for (final sf in known)
      sf: RegExp(
        '(?<![\\p{L}\\p{N}_])${RegExp.escape(sf)}s?(?![\\p{L}\\p{N}_])',
        unicode: true,
      ),
  };

  final issueChapters = <ChapterAbbreviationIssues>[];
  final counts = <String, int>{};
  final firsts = <String, (int, int)>{};
  for (var i = 0; i < chapters.length; i++) {
    final masked = _mask(plains[i]);
    final issues = <AbbreviationIssue>[];
    for (final sf in known) {
      final first = useRes[sf]!.firstMatch(masked);
      if (first == null) continue;
      final defOffsets = {
        for (final d in defs[i])
          if (d.sf == sf) d.offset,
      };
      if (!defOffsets.contains(first.start)) {
        issues.add(
          AbbreviationIssue(sf: sf, offset: first.start, length: sf.length),
        );
      }
    }
    if (issues.isNotEmpty) {
      issues.sort((a, b) => a.offset.compareTo(b.offset));
      issueChapters.add(
        ChapterAbbreviationIssues(
          noteId: chapters[i].noteId,
          title: chapters[i].title,
          issues: issues,
        ),
      );
    }

    // Abbreviation-like tokens nobody spells out.
    var pos = 0;
    for (final line in masked.split('\n')) {
      final lineStart = pos;
      pos += line.length + 1;
      final tokens = _tokenRe.allMatches(line).toList();
      final heading =
          tokens.length >= 2 &&
          !RegExp(r'\p{Ll}', unicode: true).hasMatch(line);
      if (heading) continue;
      for (final m in tokens) {
        final t = m.group(0)!;
        if (known.contains(t) ||
            (t.endsWith('s') && known.contains(t.substring(0, t.length - 1)))) {
          continue;
        }
        if (t == 'TODO' ||
            !isShortForm(t) ||
            !_undefinedShape.hasMatch(t) ||
            _roman.hasMatch(t) ||
            _panel.hasMatch(t)) {
          continue;
        }
        counts.update(t, (n) => n + 1, ifAbsent: () => 1);
        firsts.putIfAbsent(t, () => (i, lineStart + m.start));
      }
    }
  }

  final undefined =
      [
        for (final e in counts.entries)
          UndefinedAbbreviation(
            token: e.key,
            count: e.value,
            noteId: chapters[firsts[e.key]!.$1].noteId,
            title: chapters[firsts[e.key]!.$1].title,
            offset: firsts[e.key]!.$2,
          ),
      ]..sort(
        (a, b) =>
            b.count != a.count ? b.count - a.count : _bySf(a.token, b.token),
      );

  return AbbreviationReport(
    defined: defined,
    chapters: issueChapters,
    undefined: undefined,
  );
}

int _bySf(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : a.compareTo(b);
}

/// The "Abbreviations" list for an export: a level-2 heading, then one
/// paragraph per abbreviation (short form in bold, then the long form),
/// sorted by short form. Empty when nothing is spelled out.
List<ExportBlock> abbreviationBlocks(List<String> storedContents) {
  final report = analyzeAbbreviations([
    for (var i = 0; i < storedContents.length; i++)
      AbbreviationSource(noteId: '$i', title: '', content: storedContents[i]),
  ]);
  if (report.defined.isEmpty) return const [];
  return [
    const ExportBlock(BlockKind.heading2, [Run('Abbreviations')]),
    for (final d in report.defined)
      ExportBlock(BlockKind.paragraph, [
        Run(d.sf, bold: true),
        Run('  ${d.longForm}'),
      ]),
  ];
}

/// The list as a Markdown table.
String abbreviationsMarkdown(List<DefinedAbbreviation> list) =>
    '| Abbreviation | Meaning |\n| --- | --- |\n'
    '${[for (final d in list) '| ${d.sf} | ${d.longForm} |'].join('\n')}';

/// The list as tab-separated lines (pastes into a spreadsheet or Word table).
String abbreviationsTsv(List<DefinedAbbreviation> list) =>
    [for (final d in list) '${d.sf}\t${d.longForm}'].join('\n');

/// The abbreviation report for a project's notes, in chapter order.
final abbreviationsProvider = StreamProvider.autoDispose
    .family<AbbreviationReport, String>((ref, projectId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.notes).join([
        innerJoin(
          db.projectNotes,
          db.projectNotes.noteId.equalsExp(db.notes.id),
        ),
      ])..where(db.projectNotes.projectId.equals(projectId));
      return query.watch().map((rows) {
        final list = <ProjectNoteRow>[
          for (final r in rows)
            (note: r.readTable(db.notes), link: r.readTable(db.projectNotes)),
        ]..sort(compareChapterRows);
        return analyzeAbbreviations([
          for (final r in list)
            AbbreviationSource(
              noteId: r.note.id,
              title: r.note.title,
              content: r.note.content,
            ),
        ]);
      });
    });
