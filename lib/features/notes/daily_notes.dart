import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../home/adaptive.dart';
import 'daily_settings.dart';
import 'note_editor_screen.dart' show NoteEditorScreen;
import 'tags_providers.dart';
import 'templates.dart';

/// `YYYY-MM-DD` for the local calendar day of [date] (what
/// `Notes.dailyDate` stores).
String dailyKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The day a `YYYY-MM-DD` key names (local midnight), or null if it isn't
/// one.
DateTime? parseDailyKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// A daily note's title: the long date in the app's language
/// ("Wednesday, October 21, 2026").
String dailyTitle(DateTime date, String locale) =>
    DateFormat.yMMMMEEEEd(locale).format(date);

/// The id of the daily note for [key]: the oldest one if two devices each
/// made one while offline.
Future<String?> findDailyNote(AppDatabase db, String key) async {
  final rows =
      await (db.select(db.notes)
            ..where((n) => n.dailyDate.equals(key))
            ..orderBy([
              (n) => OrderingTerm.asc(n.createdAt),
              (n) => OrderingTerm.asc(n.id),
            ])
            ..limit(1))
          .get();
  return rows.firstOrNull?.id;
}

/// The id of the daily note for [now]'s day, creating it if there is none:
/// titled with the long date, its body [body] (a template's stored content
/// with the variables already filled in) and filed in [folderId]. The tags
/// of [templateId] are copied. Returns the id and whether it was created.
Future<({String id, bool created})> ensureDailyNote(
  AppDatabase db, {
  required DateTime now,
  required String locale,
  String body = '',
  String? folderId,
  String? templateId,
}) async {
  final key = dailyKey(now);
  final existing = await findDailyNote(db, key);
  if (existing != null) return (id: existing, created: false);
  final id = const Uuid().v4();
  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(dailyTitle(now, locale)),
          content: Value(body),
          folderId: Value(folderId),
          dailyDate: Value(key),
        ),
      );
  if (templateId != null) {
    final tags = await (db.select(
      db.noteTags,
    )..where((r) => r.noteId.equals(templateId))).get();
    for (final t in tags) {
      await addTagToNote(db, noteId: id, tagId: t.tagId);
    }
  }
  return (id: id, created: true);
}

/// The daily note nearest [key] before it ([previous]) or after it that
/// exists, or null. Days without a note are skipped.
Future<String?> adjacentDailyNote(
  AppDatabase db,
  String key, {
  required bool previous,
}) async {
  final rows =
      await (db.select(db.notes)
            ..where(
              (n) => previous
                  ? n.dailyDate.isSmallerThan(Variable<String>(key))
                  : n.dailyDate.isBiggerThan(Variable<String>(key)),
            )
            ..orderBy([
              (n) => previous
                  ? OrderingTerm.desc(n.dailyDate)
                  : OrderingTerm.asc(n.dailyDate),
              (n) => OrderingTerm.asc(n.createdAt),
            ])
            ..limit(1))
          .get();
  final found = rows.firstOrNull;
  if (found == null) return null;
  // Two notes can share a day; the oldest is the one that opens.
  return findDailyNote(db, found.dailyDate!);
}

/// Opens today's note — making it first, from the daily template and into
/// the daily folder if the reader chose them — in the pane or as a page,
/// like any note. [now] is for tests.
Future<void> openTodaysNote(
  BuildContext context,
  WidgetRef ref, {
  DateTime? now,
}) async {
  final db = ref.read(databaseProvider);
  final settings = ref.read(dailyNoteSettingsProvider);
  await settings.ready;
  if (!context.mounted) return;
  final moment = now ?? DateTime.now();
  final locale = context.l10n.localeName;
  final key = dailyKey(moment);

  var id = await findDailyNote(db, key);
  if (!context.mounted) return;
  if (id == null) {
    var body = '';
    final templateId = settings.templateId;
    if (templateId != null) {
      body =
          await readTemplateBody(
            context,
            ref,
            templateId,
            title: dailyTitle(moment, locale),
            now: moment,
          ) ??
          '';
      if (!context.mounted) return;
    }
    // The folder may have been deleted since it was chosen.
    final folderId = settings.folderId;
    final folderExists =
        folderId != null &&
        await (db.select(
              db.folders,
            )..where((f) => f.id.equals(folderId))).getSingleOrNull() !=
            null;
    id = (await ensureDailyNote(
      db,
      now: moment,
      locale: locale,
      body: body,
      folderId: folderExists ? folderId : null,
      templateId: body.isEmpty ? null : templateId,
    )).id;
  }
  if (!context.mounted) return;
  openNote(context, ref, id);
}

/// Opens the daily note before or after [noteId]'s day, in place of the
/// current page (or in the pane); false if there is none.
Future<bool> openNeighbouringDailyNote(
  BuildContext context,
  WidgetRef ref,
  String noteId, {
  required bool previous,
}) async {
  final db = ref.read(databaseProvider);
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  final key = note?.dailyDate;
  if (key == null) return false;
  final target = await adjacentDailyNote(db, key, previous: previous);
  if (target == null || !context.mounted) return false;
  if (hasDetailPane(context)) {
    openNote(context, ref, target);
  } else {
    // Replace the page, so Back still leads to the list.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: target)),
    );
  }
  return true;
}
