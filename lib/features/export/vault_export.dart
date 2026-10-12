import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../data/attachment_label.dart';
import '../../data/database.dart';
import '../../data/tables/attachments_table.dart';
import '../library/authors.dart';
import '../library/citation_formatter.dart';
import '../library/highlights.dart';
import '../notes/note_content.dart';
import '../notes/note_links.dart';
import '../notes/note_markdown.dart';

/// Exports the whole library as a folder of Markdown files that opens as an
/// Obsidian vault (and reads fine in any editor):
///
///     Corplex/Notes/<Folder>/<Title>.md
///     Corplex/Papers/@<citekey> <short title>.md
///     Corplex/Attachments/<files>
///     Corplex/references.bib
///
/// **Linking scheme.** Everything that points at another item is an
/// Obsidian wiki-link with an alias, so the graph and backlinks work:
/// a note link is `[[Other title]]`; a citation `[@key]` becomes
/// `[[@key Short title|@key]]` and a "— p. 4" paper link
/// `[[@key Short title|— p. 4]]`. Wiki-links win over keeping pandoc's
/// `[@key]` because Obsidian cannot link from inside a citation, while
/// pandoc users lose nothing: the alias is `@key` and `references.bib` uses
/// the same keys, so `s/\[\[[^|]*\|(@[^\]]+)\]\]/[\1]/` (or pandoc's
/// `wikilinks_title_after_pipe`) restores citations. Audio timestamp links
/// become plain `▸ 12:34` text; sketches stay `[Sketch]`.
const vaultRoot = 'Corplex';

class VaultExportResult {
  VaultExportResult(this.archive, {required this.notes, required this.papers});
  final Archive archive;
  final int notes;
  final int papers;
}

/// Builds the export in memory. [includePdfs] adds the (large) PDF files.
Future<VaultExportResult> buildVaultArchive(
  AppDatabase db, {
  bool includePdfs = false,
}) async {
  final notes = await db.select(db.notes).get();
  final papers = await db.select(db.papers).get();
  final folders = {for (final f in await db.select(db.folders).get()) f.id: f};
  final tags = {for (final t in await db.select(db.tags).get()) t.id: t.name};
  final projects = {
    for (final pr in await db.select(db.projects).get()) pr.id: pr.name,
  };
  final noteTags = await db.select(db.noteTags).get();
  final noteRefs = await db.select(db.notePaperRefs).get();
  final projectNotes = await db.select(db.projectNotes).get();
  final projectPapers = await db.select(db.projectPapers).get();
  final highlights = await db.select(db.highlights).get();
  final attachments = await db.select(db.attachments).get();

  // ---- Names -------------------------------------------------------------
  final citekeys = _uniqueCitekeys(papers);
  final paperNames = assignFileNames([
    for (final pa in papers)
      NameRequest(
        id: pa.id,
        base: '@${citekeys[pa.id]} ${_shortTitle(pa.title)}',
        created: pa.createdAt,
      ),
  ]);
  final noteNames = assignFileNames([
    for (final n in notes)
      NameRequest(
        id: n.id,
        base: n.title.trim().isEmpty ? 'Untitled' : n.title,
        created: n.createdAt,
      ),
  ]);

  // Files to include, with their names in Attachments/.
  bool wanted(Attachment a) =>
      a.path != null &&
      a.path!.isNotEmpty &&
      (includePdfs || a.type != AttachmentType.pdf);
  final attachmentNames = assignFileNames([
    for (final a in attachments)
      if (wanted(a))
        NameRequest(
          id: a.id,
          base: _attachmentBase(a),
          created: a.createdAt,
          ext: p.extension(a.path!),
        ),
  ]);
  final paperPdfNames = includePdfs
      ? assignFileNames([
          for (final pa in papers)
            if (pa.pdfPath != null && pa.pdfPath!.isNotEmpty)
              NameRequest(
                id: pa.id,
                base: '${citekeys[pa.id]} ${_shortTitle(pa.title)}',
                created: pa.createdAt,
                ext: '.pdf',
              ),
        ], taken: attachmentNames.values)
      : <String, String>{};

  final archive = Archive();
  void add(String path, String text) =>
      archive.addFile(ArchiveFile.string('$vaultRoot/$path', text));
  final copied = <String>{};
  void addFile(String name, String? source) {
    if (source == null || !copied.add(name)) return;
    final f = File(source);
    if (!f.existsSync()) return;
    archive.addFile(
      ArchiveFile.bytes('$vaultRoot/Attachments/$name', f.readAsBytesSync()),
    );
  }

  // Which attachment files really exist (so we never link to a missing one).
  final present = <String, String>{}; // attachment id -> name
  for (final a in attachments) {
    final name = attachmentNames[a.id];
    if (name != null && File(a.path!).existsSync()) present[a.id] = name;
  }
  final presentPdf = <String, String>{};
  for (final pa in papers) {
    final name = paperPdfNames[pa.id];
    if (name != null && File(pa.pdfPath!).existsSync()) {
      presentPdf[pa.id] = name;
    }
  }

  String paperLink(String paperId, [String? alias]) {
    final base = p.basenameWithoutExtension(paperNames[paperId]!);
    return alias == null ? '[[$base]]' : '[[$base|$alias]]';
  }

  // ---- Notes -------------------------------------------------------------
  final papersById = {for (final pa in papers) pa.id: pa};
  final notesById = {for (final n in notes) n.id: n};
  final byCitekey = {for (final pa in papers) citekeys[pa.id]!: pa.id};

  for (final n in notes) {
    final folder = folders[n.folderId];
    final dir = folder == null
        ? 'Notes'
        : 'Notes/${sanitizeFileName(folder.name, fallback: 'Folder')}';
    final myTags = [
      for (final t in noteTags)
        if (t.noteId == n.id && tags[t.tagId] != null) tags[t.tagId]!,
    ]..sort();
    final myProjects = [
      for (final x in projectNotes)
        if (x.noteId == n.id && projects[x.projectId] != null)
          projects[x.projectId]!,
    ]..sort();
    final myPapers = [
      for (final r in noteRefs)
        if (r.noteId == n.id && paperNames.containsKey(r.paperId)) r.paperId,
    ]..sort((a, b) => paperNames[a]!.compareTo(paperNames[b]!));

    final rewritten = _rewriteLinks(
      n.content,
      noteTitleOf: (id) => notesById.containsKey(id)
          ? p.basenameWithoutExtension(noteNames[id]!)
          : null,
      paperPage: (id, text) =>
          papersById.containsKey(id) ? paperLink(id, text) : null,
      citation: (key) {
        final id = byCitekey[key];
        return id == null ? null : paperLink(id, '@$key');
      },
    );
    final body = StringBuffer(
      noteToMarkdown(title: n.title, content: rewritten).trimRight(),
    );

    final mine = attachments.where((a) => a.noteId == n.id).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final lines = <String>[];
    for (final a in mine) {
      final name = present[a.id];
      if (name != null) {
        addFile(name, a.path);
        lines.add(
          a.type == AttachmentType.image
              ? '![[Attachments/$name]]'
              : '[[Attachments/$name]]',
        );
      } else if (a.url != null && a.url!.isNotEmpty) {
        lines.add('[${a.label}](${a.url})');
      }
    }
    if (lines.isNotEmpty) {
      body
        ..write('\n\n## Attachments\n\n')
        ..write(lines.join('\n\n'));
    }

    final fm = _frontmatter({
      'id': n.id,
      'created': n.createdAt.toUtc().toIso8601String(),
      'updated': n.updatedAt.toUtc().toIso8601String(),
      'tags': myTags,
      'projects': myProjects,
      'papers': [for (final id in myPapers) paperLink(id)],
    });
    add('$dir/${noteNames[n.id]}', '$fm\n$body\n');
  }

  // ---- Papers ------------------------------------------------------------
  for (final pa in papers) {
    final key = citekeys[pa.id]!;
    final myProjects = [
      for (final x in projectPapers)
        if (x.paperId == pa.id && projects[x.projectId] != null)
          projects[x.projectId]!,
    ]..sort();
    final authors = parseAuthors(pa.authors).authors;
    final fm = _frontmatter({
      'title': pa.title,
      'authors': [for (final a in authors) a.natural],
      'year': pa.year,
      'venue': pa.venue,
      'doi': pa.doi,
      'url': (pa.doi ?? '').isEmpty ? null : 'https://doi.org/${pa.doi}',
      'citekey': key,
      'status': pa.readingStatus?.name,
      'rating': pa.rating,
      'projects': myProjects,
    });
    final b = StringBuffer('$fm\n# ${pa.title}\n');
    if (authors.isNotEmpty) {
      b.write('\n${authors.map((a) => a.natural).join(', ')}\n');
    }
    final pdfName = presentPdf[pa.id];
    if (pdfName != null) {
      addFile(pdfName, pa.pdfPath);
      b.write('\nPDF: [[Attachments/$pdfName]]\n');
    }
    final mineHl = highlights.where((h) => h.paperId == pa.id).toList()
      ..sort((a, b) {
        final c = a.pageNumber.compareTo(b.pageNumber);
        return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
      });
    if (mineHl.isNotEmpty) {
      b.write('\n## Highlights\n');
      int? page;
      for (final h in mineHl) {
        if (h.pageNumber != page) {
          page = h.pageNumber;
          b.write('\n### p. $page\n');
        }
        final quote = h.quote.trim().replaceAll(RegExp(r'\s*\n\s*'), '\n> ');
        b.write('\n> $quote\n> — p. ${h.pageNumber}\n');
        final c = h.comment?.trim() ?? '';
        if (c.isNotEmpty) b.write('\n$c\n');
      }
    }
    final extra = <String>[];
    for (final a in attachments.where((a) => a.paperId == pa.id)) {
      final name = present[a.id];
      if (name != null) {
        addFile(name, a.path);
        extra.add(
          a.type == AttachmentType.image
              ? '![[Attachments/$name]]'
              : '[[Attachments/$name]]',
        );
      } else if (a.url != null && a.url!.isNotEmpty) {
        extra.add('[${a.label}](${a.url})');
      }
    }
    if (extra.isNotEmpty) {
      b.write('\n## Attachments\n\n${extra.join('\n\n')}\n');
    }
    add('Papers/${paperNames[pa.id]}', b.toString());
  }

  // ---- Bibliography ------------------------------------------------------
  // Keyed by the same citekeys the notes use (exportBibtex would use its own
  // Author2017Word keys, which don't match `[@vaswani2017]`).
  final bib = StringBuffer();
  for (final pa in papers) {
    final entry = formatCitation(pa, CitationStyle.bibtex);
    bib.writeln(
      entry.replaceFirstMapped(
        RegExp(r'^(@\w+)\{[^,]*,'),
        (m) => '${m[1]}{${citekeys[pa.id]},',
      ),
    );
    bib.writeln();
  }
  add('references.bib', bib.toString());

  return VaultExportResult(archive, notes: notes.length, papers: papers.length);
}

/// Writes [buildVaultArchive]'s result as a zip in [outDir].
Future<File> writeVaultZip(
  AppDatabase db, {
  required Directory outDir,
  bool includePdfs = false,
}) async {
  final result = await buildVaultArchive(db, includePdfs: includePdfs);
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final file = File(
    p.join(
      outDir.path,
      'corplex-markdown-${d.year}${two(d.month)}${two(d.day)}.zip',
    ),
  );
  file.writeAsBytesSync(ZipEncoder().encode(result.archive));
  return file;
}

// ---- Names -----------------------------------------------------------------

final _illegal = RegExp(r'[\\/:*?"<>|#^\[\]\x00-\x1f]');
const _reserved = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// A name that is safe on every platform and in Obsidian links: no path
/// separators or `: * ? " < > | # ^ [ ]`, no control characters, no
/// trailing dots/spaces, no Windows device names, at most [maxLength].
String sanitizeFileName(
  String name, {
  String fallback = 'Untitled',
  int maxLength = 80,
}) {
  var s = name.replaceAll(_illegal, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > maxLength) s = s.substring(0, maxLength).trim();
  s = s.replaceAll(RegExp(r'^\.+'), '').replaceAll(RegExp(r'[. ]+$'), '');
  if (s.isEmpty) return fallback;
  if (_reserved.contains(s.split('.').first.toLowerCase())) s = '_$s';
  return s;
}

class NameRequest {
  const NameRequest({
    required this.id,
    required this.base,
    required this.created,
    this.ext,
  });
  final String id;
  final String base;
  final DateTime created;
  final String? ext;
}

/// Gives each item a unique file name (`base + ext`, `.md` by default).
/// Items are visited oldest first (ties by id); the first keeps the plain
/// name, later ones with the same name (case-insensitive) get
/// ` (<first 8 of id>)`. A name depends only on the item and who is older,
/// so repeated exports agree. [taken] reserves names used elsewhere.
Map<String, String> assignFileNames(
  List<NameRequest> items, {
  Iterable<String> taken = const [],
}) {
  final used = {for (final t in taken) t.toLowerCase()};
  final sorted = [...items]
    ..sort((a, b) {
      final c = a.created.compareTo(b.created);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final out = <String, String>{};
  for (final it in sorted) {
    final ext = it.ext ?? '.md';
    final base = sanitizeFileName(it.base);
    var name = '$base$ext';
    if (used.contains(name.toLowerCase())) {
      final id = it.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final short = id.length > 8 ? id.substring(0, 8) : id;
      name = '$base ($short)$ext';
      var n = 2;
      while (used.contains(name.toLowerCase())) {
        name = '$base ($short-${n++})$ext';
      }
    }
    used.add(name.toLowerCase());
    out[it.id] = name;
  }
  return out;
}

String _shortTitle(String title) {
  final words = title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  var s = words.take(6).join(' ');
  if (s.length > 50) s = s.substring(0, 50);
  return sanitizeFileName(s, fallback: 'Paper', maxLength: 50);
}

String _attachmentBase(Attachment a) {
  final label = a.label;
  final ext = p.extension(a.path ?? '');
  final base = ext.isNotEmpty && label.toLowerCase().endsWith(ext.toLowerCase())
      ? label.substring(0, label.length - ext.length)
      : label;
  return base;
}

/// `citekey` per paper id: the stored one, else the BibTeX-style key, made
/// unique (`a`, `b`, … on a clash) and filename-safe.
Map<String, String> _uniqueCitekeys(List<Paper> papers) {
  final sorted = [...papers]
    ..sort((a, b) {
      final c = a.createdAt.compareTo(b.createdAt);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final used = <String>{};
  final out = <String, String>{};
  for (final pa in sorted) {
    var key = (pa.citekey?.trim().isNotEmpty ?? false)
        ? pa.citekey!.trim()
        : bibtexKey(pa);
    key = key.replaceAll(RegExp(r'[^A-Za-z0-9_:.\-]'), '');
    if (key.isEmpty) {
      key = 'paper';
    }
    var unique = key;
    var i = 0;
    while (!used.add(unique.toLowerCase())) {
      unique =
          '$key${String.fromCharCode(97 + i % 26)}${i >= 26 ? i ~/ 26 : ''}';
      i++;
    }
    out[pa.id] = unique;
  }
  return out;
}

// ---- Frontmatter -------------------------------------------------------------

String _q(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

String _frontmatter(Map<String, Object?> fields) {
  final b = StringBuffer('---\n');
  fields.forEach((k, v) {
    if (v == null) return;
    if (v is List) {
      if (v.isEmpty) {
        b.write('$k: []\n');
      } else {
        b.write('$k:\n');
        for (final item in v) {
          b.write('  - ${_q('$item')}\n');
        }
      }
    } else if (v is int) {
      b.write('$k: $v\n');
    } else if (k == 'created' || k == 'updated') {
      b.write('$k: $v\n');
    } else {
      b.write('$k: ${_q('$v')}\n');
    }
  });
  b.write('---\n');
  return b.toString();
}

// ---- Link rewriting ------------------------------------------------------------

final _citation = RegExp(r'\[(@[^\]\[]+)\]');

/// Rewrites a note's Delta so [noteToMarkdown] (which flattens Corplex's own
/// links to plain text) emits wiki-links instead.
String _rewriteLinks(
  String content, {
  required String? Function(String noteId) noteTitleOf,
  required String? Function(String paperId, String text) paperPage,
  required String? Function(String key) citation,
}) {
  final ops = decodeNoteContent(content).toDelta().toJson();
  final out = <Map<String, dynamic>>[];
  for (final raw in ops) {
    final op = Map<String, dynamic>.from(raw as Map);
    final data = op['insert'];
    if (data is! String) {
      out.add(op);
      continue;
    }
    final attrs = op['attributes'] == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(op['attributes'] as Map);
    final link = attrs['link'] as String?;
    String? replacement;
    if (link != null) {
      final noteId = parseNoteLink(link);
      final page = parsePaperPageLink(link);
      if (noteId != null) {
        final base = noteTitleOf(noteId);
        if (base != null) {
          replacement = data.trim() == base || data.trim().isEmpty
              ? '[[$base]]'
              : '[[$base|${data.replaceAll('|', ' ')}]]';
        }
      } else if (page != null) {
        replacement = paperPage(page.paperId, data.replaceAll('|', ' '));
      }
    }
    if (replacement != null) {
      attrs.remove('link');
      op['insert'] = replacement;
    } else if (link == null) {
      op['insert'] = data.replaceAllMapped(_citation, (m) {
        final parts = m.group(1)!.split(';').map((s) => s.trim()).toList();
        final linked = [
          for (final part in parts)
            citation(part.startsWith('@') ? part.substring(1) : part) ??
                '[$part]',
        ];
        return linked.join('; ');
      });
    }
    if (attrs.isEmpty) {
      op.remove('attributes');
    } else {
      op['attributes'] = attrs;
    }
    out.add(op);
  }
  return jsonEncode(out);
}
