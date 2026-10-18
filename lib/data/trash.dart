import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'database_provider.dart';
import 'tables/trash_table.dart';

/// How long deleted items are kept before being purged for good.
const trashRetention = Duration(days: 30);

List<Map<String, Object?>> _json(Iterable<Insertable> rows) => [
  for (final r in rows) (r as dynamic).toJson() as Map<String, Object?>,
];

/// Moves a note to the trash: snapshots it with its attachments, saved versions, tags,
/// paper links and project memberships, then deletes it. Returns the trash
/// item's id (for Undo).
Future<String> trashNote(AppDatabase db, String noteId) =>
    db.transaction(() async {
      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(noteId))).getSingle();
      final payload = {
        'note': (note as dynamic).toJson(),
        'attachments': _json(
          await (db.select(
            db.attachments,
          )..where((a) => a.noteId.equals(noteId))).get(),
        ),
        'tags': _json(
          await (db.select(
            db.noteTags,
          )..where((r) => r.noteId.equals(noteId))).get(),
        ),
        'papers': _json(
          await (db.select(
            db.notePaperRefs,
          )..where((r) => r.noteId.equals(noteId))).get(),
        ),
        'projects': _json(
          await (db.select(
            db.projectNotes,
          )..where((r) => r.noteId.equals(noteId))).get(),
        ),
        'versions': _json(
          await (db.select(
            db.noteVersions,
          )..where((r) => r.noteId.equals(noteId))).get(),
        ),
        'comments': _json(
          await (db.select(
            db.noteComments,
          )..where((r) => r.noteId.equals(noteId))).get(),
        ),
      };
      final id = await _store(db, TrashKind.note, noteId, note.title, payload);
      await (db.delete(db.notes)..where((n) => n.id.equals(noteId))).go();
      return id;
    });

/// Moves a paper to the trash with its attachments, highlights, ink,
/// note links and project memberships. Its PDF stays on disk until purged.
Future<String> trashPaper(AppDatabase db, String paperId) => db.transaction(
  () async {
    final paper = await (db.select(
      db.papers,
    )..where((p) => p.id.equals(paperId))).getSingle();
    final payload = {
      'paper': (paper as dynamic).toJson(),
      'attachments': _json(
        await (db.select(
          db.attachments,
        )..where((a) => a.paperId.equals(paperId))).get(),
      ),
      'highlights': _json(
        await (db.select(
          db.highlights,
        )..where((h) => h.paperId.equals(paperId))).get(),
      ),
      'annotations': _json(
        await (db.select(
          db.annotations,
        )..where((a) => a.paperId.equals(paperId))).get(),
      ),
      'notes': _json(
        await (db.select(
          db.notePaperRefs,
        )..where((r) => r.paperId.equals(paperId))).get(),
      ),
      'projects': _json(
        await (db.select(
          db.projectPapers,
        )..where((r) => r.paperId.equals(paperId))).get(),
      ),
    };
    final id = await _store(db, TrashKind.paper, paperId, paper.title, payload);
    await (db.delete(db.papers)..where((p) => p.id.equals(paperId))).go();
    return id;
  },
);

Future<String> _store(
  AppDatabase db,
  TrashKind kind,
  String itemId,
  String title,
  Map<String, Object?> payload,
) async {
  final row = TrashItemsCompanion.insert(
    kind: kind,
    itemId: itemId,
    title: Value(title),
    payloadJson: jsonEncode(payload),
  );
  await db.into(db.trashItems).insert(row);
  final stored =
      await (db.select(db.trashItems)
            ..where((t) => t.itemId.equals(itemId))
            ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)])
            ..limit(1))
          .getSingle();
  return stored.id;
}

/// Puts a trashed note or paper back, with everything that went with it.
/// Rows that pointed at something since deleted (a folder, a tag, a paper
/// the note cited…) are restored without that link. Every restored row is
/// stamped "now", so the restore syncs — a delete elsewhere would
/// otherwise win on its newer timestamp.
Future<void> restoreFromTrash(
  AppDatabase db,
  String trashId,
) => db.transaction(() async {
  final item = await (db.select(
    db.trashItems,
  )..where((t) => t.id.equals(trashId))).getSingleOrNull();
  if (item == null) return;
  final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
  final now = DateTime.now();

  List<Map<String, dynamic>> list(String key) => [
    for (final r in (payload[key] as List? ?? const []))
      (r as Map).cast<String, dynamic>(),
  ];

  // Deleting the row let cloud cleanup remove its file. If the file is still
  // on this device, forget the cloud copy so the restore uploads it again.
  Map<String, dynamic> reupload(Map<String, dynamic> json, String pathKey) {
    final path = json[pathKey] as String?;
    return path != null && File(path).existsSync()
        ? {...json, 'storageKey': null}
        : json;
  }

  Future<bool> exists(String table, String column, Object? value) async =>
      (await db
              .customSelect(
                'SELECT 1 FROM $table WHERE $column = ?',
                variables: [Variable(value)],
              )
              .get())
          .isNotEmpty;

  if (item.kind == TrashKind.note) {
    final json = (payload['note'] as Map).cast<String, dynamic>();
    final folderId = json['folderId'] as String?;
    final note = Note.fromJson({
      ...json,
      'folderId': folderId != null && await exists('folders', 'id', folderId)
          ? folderId
          : null,
      'updatedAt': now.millisecondsSinceEpoch,
    });
    await db.into(db.notes).insertOnConflictUpdate(note);
    for (final a in list('attachments')) {
      await db
          .into(db.attachments)
          .insertOnConflictUpdate(
            Attachment.fromJson({
              ...reupload(a, 'path'),
              'updatedAt': now.millisecondsSinceEpoch,
            }),
          );
    }
    for (final v in list('versions')) {
      await db
          .into(db.noteVersions)
          .insertOnConflictUpdate(
            NoteVersion.fromJson({
              ...v,
              'updatedAt': now.millisecondsSinceEpoch,
            }),
          );
    }
    for (final r in list('comments')) {
      await db
          .into(db.noteComments)
          .insertOnConflictUpdate(
            NoteComment.fromJson({
              ...r,
              'updatedAt': now.millisecondsSinceEpoch,
            }),
          );
    }
    for (final r in list('tags')) {
      if (await exists('tags', 'id', r['tagId'])) {
        await db
            .into(db.noteTags)
            .insertOnConflictUpdate(
              NoteTag.fromJson({...r, 'updatedAt': now.millisecondsSinceEpoch}),
            );
      }
    }
    for (final r in list('papers')) {
      if (await exists('papers', 'id', r['paperId'])) {
        await db
            .into(db.notePaperRefs)
            .insertOnConflictUpdate(
              NotePaperRef.fromJson({
                ...r,
                'updatedAt': now.millisecondsSinceEpoch,
              }),
            );
      }
    }
    for (final r in list('projects')) {
      if (await exists('projects', 'id', r['projectId'])) {
        await db
            .into(db.projectNotes)
            .insertOnConflictUpdate(
              ProjectNote.fromJson({
                ...r,
                'updatedAt': now.millisecondsSinceEpoch,
              }),
            );
      }
    }
  } else {
    final paper = Paper.fromJson({
      ...reupload((payload['paper'] as Map).cast<String, dynamic>(), 'pdfPath'),
      'updatedAt': now.millisecondsSinceEpoch,
    });
    await db.into(db.papers).insertOnConflictUpdate(paper);
    for (final a in list('attachments')) {
      await db
          .into(db.attachments)
          .insertOnConflictUpdate(
            Attachment.fromJson({
              ...reupload(a, 'path'),
              'updatedAt': now.millisecondsSinceEpoch,
            }),
          );
    }
    for (final h in list('highlights')) {
      await db
          .into(db.highlights)
          .insertOnConflictUpdate(
            Highlight.fromJson({...h, 'updatedAt': now.millisecondsSinceEpoch}),
          );
    }
    for (final a in list('annotations')) {
      await db
          .into(db.annotations)
          .insertOnConflictUpdate(
            Annotation.fromJson({
              ...a,
              'updatedAt': now.millisecondsSinceEpoch,
            }),
          );
    }
    for (final r in list('notes')) {
      if (await exists('notes', 'id', r['noteId'])) {
        await db
            .into(db.notePaperRefs)
            .insertOnConflictUpdate(
              NotePaperRef.fromJson({
                ...r,
                'updatedAt': now.millisecondsSinceEpoch,
              }),
            );
      }
    }
    for (final r in list('projects')) {
      if (await exists('projects', 'id', r['projectId'])) {
        await db
            .into(db.projectPapers)
            .insertOnConflictUpdate(
              ProjectPaper.fromJson({
                ...r,
                'updatedAt': now.millisecondsSinceEpoch,
              }),
            );
      }
    }
  }
  await (db.delete(db.trashItems)..where((t) => t.id.equals(trashId))).go();
});

/// Deletes trash entries older than [retention] (or everything with
/// [all]), and the files only they referenced. Returns how many entries
/// were purged.
Future<int> purgeTrash(
  AppDatabase db, {
  Duration retention = trashRetention,
  bool all = false,
  DateTime? now,
}) async {
  final cutoff = (now ?? DateTime.now()).subtract(retention);
  final expired =
      await (db.select(db.trashItems)..where(
            (t) => all
                ? const Constant(true)
                : t.deletedAt.isSmallerThanValue(cutoff),
          ))
          .get();
  for (final item in expired) {
    final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
    final paths = <String>[
      for (final a in (payload['attachments'] as List? ?? const []))
        if ((a as Map)['path'] case final String path) path,
      if (payload['paper'] case final Map paper)
        if (paper['pdfPath'] case final String path) path,
    ];
    await (db.delete(db.trashItems)..where((t) => t.id.equals(item.id))).go();
    // A marked-up image (features/markup) keeps its untouched original and
    // its strokes in a sidecar `<name>.markup.json` beside the composite;
    // they go with it.
    for (final path in [...paths]) {
      final sidecar = File('${p.withoutExtension(path)}.markup.json');
      try {
        if (!sidecar.existsSync()) continue;
        final original =
            (jsonDecode(sidecar.readAsStringSync()) as Map)['original'];
        if (original is String) paths.add(original);
        paths.add(sidecar.path);
      } catch (_) {}
    }
    for (final path in paths) {
      // A file another row (or another trash entry) still points at stays.
      final used = await db
          .customSelect(
            'SELECT 1 FROM attachments WHERE path = ? UNION ALL '
            'SELECT 1 FROM papers WHERE pdf_path = ? UNION ALL '
            "SELECT 1 FROM trash_items WHERE payload_json LIKE ? LIMIT 1",
            variables: [
              Variable(path),
              Variable(path),
              Variable('%${jsonEncode(path).replaceAll('%', r'\%')}%'),
            ],
          )
          .get();
      if (used.isEmpty) {
        try {
          final file = File(path);
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }
    }
  }
  return expired.length;
}

final trashItemsProvider = StreamProvider.autoDispose<List<TrashItem>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.trashItems,
  )..orderBy([(t) => OrderingTerm.desc(t.deletedAt)])).watch();
});
