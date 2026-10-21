import 'package:drift/drift.dart' show Value;
import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/notes/daily_notes.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/notes_providers.dart';
import 'package:corplex/features/notes/templates.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => initializeDateFormatting('en'));
  setUp(() => db = AppDatabase.inMemoryForTesting());
  tearDown(() => db.close());

  group('daily notes', () {
    final day = DateTime(2026, 10, 21, 15, 30);

    test('keys are local dates', () {
      expect(dailyKey(DateTime(2026, 3, 4)), '2026-03-04');
      expect(parseDailyKey('2026-03-04'), DateTime(2026, 3, 4));
      expect(parseDailyKey('March'), isNull);
      expect(dailyTitle(day, 'en'), 'Wednesday, October 21, 2026');
    });

    test('creates today once, with title, body and folder', () async {
      await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(id: const Value('f'), name: 'Log'));
      final first = await ensureDailyNote(
        db,
        now: day,
        locale: 'en',
        body: '[{"insert":"plan\\n"}]',
        folderId: 'f',
      );
      expect(first.created, isTrue);
      final again = await ensureDailyNote(db, now: day, locale: 'en');
      expect(again.created, isFalse);
      expect(again.id, first.id);

      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(first.id))).getSingle();
      expect(note.dailyDate, '2026-10-21');
      expect(note.title, 'Wednesday, October 21, 2026');
      expect(note.folderId, 'f');
      expect(note.content, contains('plan'));
      expect(await db.select(db.notes).get(), hasLength(1));
    });

    test('the oldest wins when two devices each made one', () async {
      for (final (id, created) in [
        ('newer', DateTime(2026, 10, 21, 9)),
        ('older', DateTime(2026, 10, 21, 8)),
      ]) {
        await db
            .into(db.notes)
            .insert(
              NotesCompanion.insert(
                id: Value(id),
                dailyDate: const Value('2026-10-21'),
                createdAt: Value(created),
              ),
            );
      }
      expect(await findDailyNote(db, '2026-10-21'), 'older');
      final result = await ensureDailyNote(db, now: day, locale: 'en');
      expect(result.id, 'older');
    });

    test('previous and next skip days without a note', () async {
      for (final d in ['2026-10-01', '2026-10-10', '2026-10-21']) {
        await db
            .into(db.notes)
            .insert(
              NotesCompanion.insert(id: Value('d$d'), dailyDate: Value(d)),
            );
      }
      expect(
        await adjacentDailyNote(db, '2026-10-10', previous: true),
        'd2026-10-01',
      );
      expect(
        await adjacentDailyNote(db, '2026-10-10', previous: false),
        'd2026-10-21',
      );
      expect(await adjacentDailyNote(db, '2026-10-01', previous: true), isNull);
      expect(
        await adjacentDailyNote(db, '2026-10-21', previous: false),
        isNull,
      );
    });

    test('copies the template tags onto a new daily note', () async {
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: const Value('t'), name: 'daily'));
      await db
          .into(db.notes)
          .insert(NotesCompanion.insert(id: const Value('tpl')));
      await db
          .into(db.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: 'tpl', tagId: 't'));
      final r = await ensureDailyNote(
        db,
        now: day,
        locale: 'en',
        templateId: 'tpl',
      );
      final tags = await (db.select(
        db.noteTags,
      )..where((x) => x.noteId.equals(r.id))).get();
      expect(tags.map((t) => t.tagId), ['t']);
    });
  });

  group('lists', () {
    setUp(() async {
      await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(id: const Value('f'), name: 'F'));
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('plain'),
              title: const Value('Plain'),
              folderId: const Value('f'),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('tpl'),
              title: const Value('Meeting'),
              folderId: const Value('f'),
              isTemplate: const Value(true),
            ),
          );
    });

    Future<List<String>> titles(NotesFilter filter) async => [
      for (final n in await watchNoteList(db, filter).first) n.title,
    ];

    test('templates leave every ordinary list', () async {
      expect(await titles(const AllNotes()), ['Plain']);
      expect(await titles(const FolderFilter('f')), ['Plain']);
    });

    test('the Templates filter lists only templates', () async {
      expect(await titles(const TemplatesFilter()), ['Meeting']);
    });

    test('tag and project filters hide templates too', () async {
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: const Value('t'), name: 'x'));
      await db
          .into(db.projects)
          .insert(ProjectsCompanion.insert(id: const Value('p'), name: 'P'));
      for (final id in ['plain', 'tpl']) {
        await db
            .into(db.noteTags)
            .insert(NoteTagsCompanion.insert(noteId: id, tagId: 't'));
        await db
            .into(db.projectNotes)
            .insert(ProjectNotesCompanion.insert(projectId: 'p', noteId: id));
      }
      expect(await titles(const TagFilter('t')), ['Plain']);
      expect(await titles(const ProjectFilter('p')), ['Plain']);
    });

    test('setNoteTemplate moves a note between the lists', () async {
      await setNoteTemplate(db, 'plain', true);
      expect(await titles(const AllNotes()), isEmpty);
      expect(
        await titles(const TemplatesFilter()),
        unorderedEquals(['Meeting', 'Plain']),
      );
      await setNoteTemplate(db, 'tpl', false);
      expect(await titles(const AllNotes()), ['Meeting']);
    });
  });

  group('insertTemplateBody', () {
    QuillController controllerWith(String text) => QuillController(
      document: Document()..insert(0, text),
      selection: const TextSelection.collapsed(offset: 0),
    );

    test('inserts on a fresh line with formatting and chips', () {
      final c = controllerWith('Intro');
      final stored = encodeNoteContent(
        Document.fromJson([
          {'insert': 'Notes'},
          {
            'insert': '\n',
            'attributes': {'header': 2},
          },
          {'insert': 'see [@kandel2013] and \$x\$\n'},
        ]),
      );
      final end = insertTemplateBody(c, 5, stored);
      final text = c.document.toPlainText();
      expect(text.startsWith('Intro\nNotes\n'), isTrue);
      // The citation and maths became one-character chips.
      expect(text, isNot(contains('[@kandel2013]')));
      final ops = c.document.toDelta().toJson();
      expect(
        ops.any(
          (o) => o['insert'] is Map && (o['insert'] as Map).containsKey('cite'),
        ),
        isTrue,
      );
      expect(
        ops.any(
          (o) =>
              o['insert'] == '\n' && (o['attributes'] as Map?)?['header'] == 2,
        ),
        isTrue,
      );
      expect(c.selection.baseOffset, end);
      expect(end, text.indexOf('\n', text.indexOf('see')));
    });

    test('into an empty line needs no extra newline', () {
      final c = controllerWith('');
      insertTemplateBody(
        c,
        0,
        encodeNoteContent(Document()..insert(0, 'Body')),
      );
      expect(c.document.toPlainText(), 'Body\n\n');
    });
  });
}
