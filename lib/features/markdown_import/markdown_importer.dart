import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/tables/attachments_table.dart';
import '../notes/folders_providers.dart' show createFolder;
import '../notes/note_content.dart';
import '../notes/tags_providers.dart' show addTagToNote, findOrCreateTag;
import 'markdown_to_delta.dart';
import 'vault_source.dart';

/// What an import did, for the summary dialog.
class MdImportSummary {
  const MdImportSummary({
    this.notes = 0,
    this.attachments = 0,
    this.unresolved = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  /// Notes created.
  final int notes;

  /// Files copied in as attachments.
  final int attachments;

  /// Links and embeds that matched nothing and stayed text.
  final int unresolved;

  /// Notes not imported: Corplex's own paper pages, locked placeholders,
  /// and notes already there with the same text.
  final int skipped;

  /// Notes that could not be saved.
  final int failed;
}

const _imageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.heic',
  '.heif',
  '.webp',
  '.tif',
  '.tiff',
  '.bmp',
};

const _audioExtensions = {
  '.mp3',
  '.m4a',
  '.wav',
  '.aac',
  '.ogg',
  '.oga',
  '.opus',
  '.flac',
};

/// How an attached file is shown: images get previews, audio plays, the
/// rest (PDFs, drawings as SVG, anything) are file attachments.
AttachmentType attachmentTypeForPath(String path) {
  final ext = p.extension(path).toLowerCase();
  if (_imageExtensions.contains(ext)) return AttachmentType.image;
  if (_audioExtensions.contains(ext)) return AttachmentType.podcast;
  return AttachmentType.file;
}

class _Entry {
  _Entry(this.file, this.id);

  final MdSourceFile file;
  final String id;
  late String dir; // vault directory of the file, '' at the root
  String? folder;
  late String fileTitle;
  late String title;
  List<String> aliases = const [];
  late MdFrontmatter frontmatter;
  late String text;
  final blocks = <String, String>{};
  MdConversion? conversion;
  String? existingId; // a note already there with the same text
}

/// The vault's notes and files, and how links find them (Obsidian's rules:
/// a bare name matches a note in any folder, the nearest one winning).
class _Index {
  final entries = <_Entry>[];
  final byName = <String, List<_Entry>>{};
  final byTitle = <String, List<_Entry>>{};
  final byAlias = <String, List<_Entry>>{};
  final byPath = <String, List<_Entry>>{};
  final byId = <String, _Entry>{};
  final filePaths = <String, String>{}; // lower -> real
  final filesByName = <String, List<String>>{};

  void add(_Entry e) {
    entries.add(e);
    byId[e.id] = e;
    final noExt = p.posix.withoutExtension(e.file.path).toLowerCase();
    (byPath[noExt] ??= []).add(e);
    (byName[p.posix.basename(noExt)] ??= []).add(e);
    (byTitle[e.title.toLowerCase()] ??= []).add(e);
    for (final a in e.aliases) {
      (byAlias[a.toLowerCase()] ??= []).add(e);
    }
  }

  void addFile(String path) {
    filePaths[path.toLowerCase()] = path;
    (filesByName[p.posix.basename(path).toLowerCase()] ??= []).add(path);
  }

  _Entry? _best(List<_Entry>? list, _Entry from) {
    if (list == null || list.isEmpty) return null;
    for (final e in list) {
      if (e.dir == from.dir) return e;
    }
    return list.first;
  }

  static String _normalise(String target) {
    var t = target.replaceAll('\\', '/').trim();
    while (t.startsWith('./')) {
      t = t.substring(2);
    }
    return t;
  }

  _Entry? resolveNote(String target, _Entry from) {
    var t = _normalise(target);
    if (t.toLowerCase().endsWith('.md')) t = t.substring(0, t.length - 3);
    if (t.toLowerCase().endsWith('.markdown')) t = t.substring(0, t.length - 9);
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    // Relative to the linking note, then from the vault root.
    final rel = p.posix.normalize(p.posix.join(from.dir, lower));
    final direct = byPath[rel]?.firstOrNull ?? byPath[lower]?.firstOrNull;
    if (direct != null) return direct;
    if (lower.contains('/')) {
      final hits = [
        for (final e in entries)
          if (p.posix
              .withoutExtension(e.file.path)
              .toLowerCase()
              .endsWith('/$lower'))
            e,
      ];
      final best = _best(hits, from);
      if (best != null) return best;
      return null;
    }
    return _best(byName[lower], from) ??
        _best(byTitle[lower], from) ??
        _best(byAlias[lower], from);
  }

  String? resolveFile(String target, _Entry from) {
    final t = _normalise(target);
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    final rel = p.posix.normalize(p.posix.join(from.dir, lower));
    final direct = filePaths[rel] ?? filePaths[lower];
    if (direct != null) return direct;
    if (lower.contains('/')) {
      final hits = filePaths.keys.where((k) => k.endsWith('/$lower')).toList()
        ..sort();
      return hits.isEmpty ? null : filePaths[hits.first];
    }
    final named = filesByName[lower];
    if (named == null || named.isEmpty) return null;
    final fromDir = from.dir;
    for (final path in named) {
      if (p.posix.dirname(path) == (fromDir.isEmpty ? '.' : fromDir)) {
        return path;
      }
    }
    return named.first;
  }
}

class _NoteResolver implements MdResolver {
  _NoteResolver(this.index, this.from);
  final _Index index;
  final _Entry from;

  @override
  MdNoteRef? note(String target) {
    final e = index.resolveNote(target, from);
    return e == null ? null : MdNoteRef(e.id, e.title);
  }

  @override
  String? file(String target) => index.resolveFile(target, from);

  @override
  String? blockPreview(String noteId, String blockId) =>
      index.byId[noteId]?.blocks[blockId];
}

final _blockLine = RegExp(r'^(.*\S)\s\^([A-Za-z0-9-]+)\s*$', multiLine: true);

String _previewOf(String line) {
  var s = line
      .replaceFirst(
        RegExp(r'^\s*(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)'),
        '',
      )
      .replaceAll(RegExp(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]'), r'$1')
      .replaceAll(RegExp(r'[*_=~`]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > 40) s = '${s.substring(0, 40).trimRight()}…';
  return s;
}

/// Imports Markdown notes (an Obsidian vault, a folder, loose files) into
/// the library. Pass 1 gives every note an id and builds the link index;
/// pass 2 converts each note with links resolved; then each note commits
/// in its own transaction (so a failure loses one note, not the import),
/// yielding between notes so the UI stays responsive.
///
/// Skipped: hidden files and folders, Corplex's own paper pages
/// (`Papers/@…` with a `citekey`), locked-note placeholders, and a note
/// whose title, folder and text equal one already in the library.
Future<MdImportSummary> importMarkdown(
  AppDatabase db,
  List<MdSourceFile> files, {
  void Function(int done, int total)? onProgress,
}) async {
  final all = [
    for (final f in files)
      if (!isIgnoredVaultPath(f.path)) f,
  ];
  final markdown = [
    for (final f in all)
      if (isMarkdownPath(f.path)) f,
  ];

  // Corplex's own export keeps notes under Notes/ beside Papers/ and
  // Attachments/: the Notes/ level isn't a folder.
  final paths = [for (final f in all) f.path];
  final corplexLayout =
      paths.contains('references.bib') ||
      (paths.any((x) => x.startsWith('Notes/')) &&
          paths.any(
            (x) => x.startsWith('Papers/') || x.startsWith('Attachments/'),
          ));

  final index = _Index();
  for (final f in all) {
    if (!isMarkdownPath(f.path)) index.addFile(f.path);
  }

  var skipped = 0;
  const uuid = Uuid();
  for (final f in markdown) {
    final e = _Entry(f, uuid.v4());
    e.text = await f.readText();
    final split = splitFrontmatter(e.text);
    e.frontmatter = split.frontmatter;
    e.fileTitle = p.posix.basenameWithoutExtension(f.path);
    final dirName = p.posix.dirname(f.path);
    e.dir = dirName == '.' ? '' : dirName;

    final fm = e.frontmatter;
    final isPaperPage =
        fm.citekey != null &&
        (e.fileTitle.startsWith('@') || e.dir.split('/').contains('Papers'));
    if (fm.locked || isPaperPage) {
      skipped++;
      continue;
    }
    var segments = e.dir.isEmpty ? <String>[] : e.dir.split('/');
    if (corplexLayout && segments.isNotEmpty && segments.first == 'Notes') {
      segments = segments.sublist(1);
    }
    e.folder = segments.isEmpty ? null : segments.join(' / ');
    e.title = matchingLeadingTitle(split.body, e.fileTitle) ?? e.fileTitle;
    e.aliases = fm.aliases;
    for (final m in _blockLine.allMatches(split.body)) {
      e.blocks.putIfAbsent(m.group(2)!, () => _previewOf(m.group(1)!));
    }
    index.add(e);
  }

  // Pass 2: convert with links resolved.
  for (final e in index.entries) {
    e.conversion = markdownToDelta(
      e.text,
      resolver: _NoteResolver(index, e),
      fileTitle: e.fileTitle,
      selfId: e.id,
    );
    e.title = e.conversion!.title;
  }

  // Already there? Same title, same folder, same text.
  final folderIds = {
    for (final f in await db.select(db.folders).get())
      f.name.toLowerCase(): f.id,
  };
  final remap = <String, String>{};
  for (final e in index.entries) {
    final folderId = e.folder == null
        ? null
        : folderIds[e.folder!.toLowerCase()];
    if (e.folder != null && folderId == null) continue;
    final same =
        await (db.select(db.notes)
              ..where((n) => n.title.equals(e.title))
              ..where(
                (n) => folderId == null
                    ? n.folderId.isNull()
                    : n.folderId.equals(folderId),
              ))
            .get();
    final mine = e.conversion!.plainText.trim();
    for (final n in same) {
      final theirs = decodeNoteContent(n.content).toPlainText().trim();
      if (theirs == mine) {
        e.existingId = n.id;
        remap[e.id] = n.id;
        break;
      }
    }
  }

  final todo = [
    for (final e in index.entries)
      if (e.existingId == null) e,
  ];
  skipped += index.entries.length - todo.length;

  final sourceByPath = {for (final f in all) f.path: f};
  var made = 0;
  var attached = 0;
  var unresolved = 0;
  var failed = 0;
  onProgress?.call(0, todo.length);
  for (final e in todo) {
    final conv = e.conversion!;
    var content = conv.content;
    if (remap.isNotEmpty && content.contains('corplex://note/')) {
      remap.forEach((from, to) => content = content.replaceAll(from, to));
    }
    final copied = <String>[];
    try {
      String? folderId;
      if (e.folder != null) {
        folderId = folderIds[e.folder!.toLowerCase()] ??= await createFolder(
          db,
          e.folder!,
        );
      }
      final attachments = <(String path, String name, AttachmentType type)>[];
      for (final vaultPath in conv.attachments) {
        final source = sourceByPath[vaultPath];
        if (source == null) continue;
        final local = await source.copyToAppStorage('attachments');
        copied.add(local);
        final name = p.posix.basename(vaultPath);
        final type = attachmentTypeForPath(vaultPath);
        attachments.add((
          local,
          type == AttachmentType.podcast ? _audioTitle(name) : name,
          type,
        ));
      }
      final now = DateTime.now();
      final created = e.frontmatter.created ?? e.file.modified ?? now;
      final updated = e.frontmatter.updated ?? e.file.modified ?? now;
      final tagNames = <String>[];
      final seen = <String>{};
      for (final t in [...e.frontmatter.tags, ...conv.tags]) {
        if (seen.add(t.toLowerCase())) tagNames.add(t);
      }
      await db.transaction(() async {
        await db
            .into(db.notes)
            .insert(
              NotesCompanion(
                id: Value(e.id),
                title: Value(e.title),
                content: Value(content),
                folderId: Value(folderId),
                aliases: Value(
                  e.aliases.isEmpty
                      ? null
                      : e.aliases.map((a) => a.replaceAll(';', ',')).join('; '),
                ),
                createdAt: Value(created),
                updatedAt: Value(updated.isBefore(created) ? created : updated),
              ),
            );
        for (final t in tagNames) {
          await addTagToNote(
            db,
            noteId: e.id,
            tagId: await findOrCreateTag(db, t),
          );
        }
        for (final a in attachments) {
          await db
              .into(db.attachments)
              .insert(
                AttachmentsCompanion.insert(
                  id: Value(uuid.v4()),
                  noteId: Value(e.id),
                  type: a.$3,
                  path: Value(a.$1),
                  title: Value(a.$2),
                ),
              );
        }
      });
      made++;
      attached += attachments.length;
      unresolved += conv.unresolved;
    } catch (_) {
      failed++;
      for (final path in copied) {
        try {
          File(path).deleteSync();
        } on FileSystemException {
          // Leave it; a stray file costs nothing.
        }
      }
    }
    onProgress?.call(made + failed, todo.length);
    await Future<void>.delayed(Duration.zero);
  }

  return MdImportSummary(
    notes: made,
    attachments: attached,
    unresolved: unresolved,
    skipped: skipped,
    failed: failed,
  );
}

String _audioTitle(String name) {
  var t = p.basenameWithoutExtension(name).replaceAll('_', ' ');
  if (!t.contains(' ')) t = t.replaceAll('-', ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? name : t;
}
