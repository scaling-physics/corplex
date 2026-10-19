import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:corplex/features/notes/note_drop.dart';
import 'package:corplex/features/notes/note_file_actions.dart';
import 'package:corplex/features/notes/notes_providers.dart';
import 'package:corplex/features/notes/notes_screen.dart';
import 'package:corplex/l10n/l10n.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

class _FakeClipboard implements NoteClipboard {
  List<String> copiedFiles = const [];
  Uint8List? copiedImage;

  @override
  Future<List<String>> files() async => copiedFiles;
  @override
  Future<Uint8List?> image() async => copiedImage;
}

class _OfflineClient extends Fake implements http.Client {}

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    tmp = Directory.systemTemp.createTempSync('corplex_notefiles');
    PathProviderPlatform.instance = _FakePathProvider('${tmp.path}/docs');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  group('date sections', () {
    setUpAll(() => initializeDateFormatting('en'));
    final now = DateTime(2026, 10, 18, 9);
    final l10n = lookupAppLocalizations(const Locale('en'));
    NoteListItem note(DateTime updated, {bool pinned = false}) => NoteListItem(
      id: 'x',
      title: '',
      folderId: null,
      preview: '',
      locked: false,
      createdAt: updated,
      updatedAt: updated,
      pinned: pinned,
    );

    test('Notes-style groups', () {
      expect(
        noteDateSection(note(DateTime(2026, 10, 18, 8)), now, l10n),
        'Today',
      );
      expect(
        noteDateSection(note(DateTime(2026, 10, 17, 23)), now, l10n),
        'Yesterday',
      );
      expect(
        noteDateSection(note(DateTime(2026, 10, 13)), now, l10n),
        'Previous 7 Days',
      );
      expect(
        noteDateSection(note(DateTime(2026, 9, 25)), now, l10n),
        'Previous 30 Days',
      );
      expect(noteDateSection(note(DateTime(2026, 3, 2)), now, l10n), 'March');
      expect(noteDateSection(note(DateTime(2024, 12, 30)), now, l10n), '2024');
      expect(
        noteDateSection(note(DateTime(2020), pinned: true), now, l10n),
        'Pinned',
      );
    });

    test('a header only where the group changes', () {
      final notes = [
        note(DateTime(2020), pinned: true),
        note(DateTime(2026, 10, 18, 8)),
        note(DateTime(2026, 10, 18, 7)),
        note(DateTime(2026, 3, 2)),
      ];
      expect(noteSectionHeaders(notes, now, l10n), [
        'Pinned',
        'Today',
        null,
        'March',
      ]);
    });
  });

  group('duplicate', () {
    NoteLockService lock() => NoteLockService(
      db,
      crypto: NoteCrypto(iterations: 1000),
      inlineKdf: true,
    );

    Future<void> seed({required String content}) async {
      await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(id: const Value('f'), name: 'Lab'));
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: const Value('t'), name: 'mPFC'));
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 'P'));
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Grant'),
              content: Value(content),
              folderId: const Value('f'),
              pinned: const Value(true),
            ),
          );
      await db
          .into(db.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: 'n1', tagId: 't'));
      await db
          .into(db.notePaperRefs)
          .insert(NotePaperRefsCompanion.insert(noteId: 'n1', paperId: 'p'));
      final audio = File('${tmp.path}/talk.m4a')..writeAsBytesSync([1, 2, 3]);
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: const Value('a1'),
              noteId: const Value('n1'),
              type: AttachmentType.podcast,
              path: Value(audio.path),
              title: const Value('Talk'),
            ),
          );
    }

    const body =
        '[{"insert":"See "},{"insert":"▸ 1:02","attributes":'
        '{"link":"corplex://audio/a1?t=62"}},{"insert":"\\n"}]';

    test('copies the note, its links and its files', () async {
      await seed(content: body);
      final id = await duplicateNote(db, lock(), 'n1');

      final copy = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(id))).getSingle();
      expect(copy.title, 'Grant');
      expect(copy.folderId, 'f');
      expect(copy.pinned, isFalse);
      final tags = await (db.select(
        db.noteTags,
      )..where((t) => t.noteId.equals(id))).get();
      expect(tags.map((t) => t.tagId), ['t']);
      final refs = await (db.select(
        db.notePaperRefs,
      )..where((r) => r.noteId.equals(id))).get();
      expect(refs.map((r) => r.paperId), ['p']);

      final attachment = await (db.select(
        db.attachments,
      )..where((a) => a.noteId.equals(id))).getSingle();
      expect(attachment.id, isNot('a1'));
      expect(attachment.path, startsWith('${tmp.path}/docs/attachments/'));
      expect(File(attachment.path!).readAsBytesSync(), [1, 2, 3]);
      // The timestamp plays the copy's own recording.
      expect(copy.content, contains('corplex://audio/${attachment.id}?t=62'));
      expect(copy.content, isNot(contains('audio/a1')));
      // The original is untouched.
      final original = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('n1'))).getSingle();
      expect(original.content, body);
    });

    test('a locked note is copied locked, readable under its own id', () async {
      await seed(content: body);
      final service = lock();
      await service.setPassword('hunter22');
      await service.lockNote('n1');
      final id = await duplicateNote(db, service, 'n1');
      final copy = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(id))).getSingle();
      expect(isLockedContent(copy.content), isTrue);
      final plain = await service.decryptBody(id, copy.content);
      expect(plain, contains('See '));
      expect(plain, isNot(contains('audio/a1')));

      service.lockNow();
      expect(
        () => duplicateNote(db, service, 'n1'),
        throwsA(isA<NoteLockedException>()),
      );
    });
  });

  test('file kinds', () {
    expect(noteFileKind('/x/Paper.PDF'), NoteFileKind.pdf);
    expect(noteFileKind('/x/shot.png'), NoteFileKind.image);
    expect(noteFileKind('/x/IMG_1.HEIC'), NoteFileKind.image);
    expect(noteFileKind('/x/overview.m4a'), NoteFileKind.audio);
    expect(noteFileKind('/x/data.csv'), NoteFileKind.file);
  });

  group('paste and drop', () {
    late _FakeClipboard clipboard;
    late WidgetRef widgetRef;
    late BuildContext widgetContext;

    setUp(() async {
      clipboard = _FakeClipboard();
      await db
          .into(db.notes)
          .insert(NotesCompanion.insert(id: const Value('n1')));
    });

    Future<void> host(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            noteClipboardProvider.overrideWithValue(clipboard),
            metadataLookupProvider.overrideWithValue(
              MetadataLookup(client: _OfflineClient()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  widgetRef = ref;
                  widgetContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
    }

    Future<List<Attachment>> attachments() =>
        (db.select(db.attachments)..where((a) => a.noteId.equals('n1'))).get();

    testWidgets('files become attachments; a PDF becomes a linked paper', (
      tester,
    ) async {
      await host(tester);
      final files = [
        File('${tmp.path}/Figure 2.png')..writeAsBytesSync([1]),
        File('${tmp.path}/Audio_Overview.m4a')..writeAsBytesSync([2]),
        File('${tmp.path}/results.csv')..writeAsBytesSync([3]),
        File('${tmp.path}/Attention Is All You Need.pdf')
          ..writeAsBytesSync([37, 80, 68, 70]),
      ];
      Directory('${tmp.path}/a folder').createSync();
      final added = await tester.runAsync(
        () => addFilesToNote(widgetContext, widgetRef, 'n1', [
          for (final f in files) f.path,
          '${tmp.path}/a folder',
        ]),
      );
      expect(added, 4);
      await tester.runAsync(() async {
        final rows = await attachments();
        expect(
          {for (final a in rows) a.type: a.title},
          {
            AttachmentType.image: 'Figure 2.png',
            AttachmentType.podcast: 'Audio Overview',
            AttachmentType.file: 'results.csv',
          },
        );
        for (final a in rows) {
          expect(a.path, startsWith('${tmp.path}/docs/attachments/'));
        }
        final paper = await db.select(db.papers).getSingle();
        expect(paper.title, 'Attention Is All You Need');
        final refs = await db.select(db.notePaperRefs).get();
        expect(refs.map((r) => (r.noteId, r.paperId)), [('n1', paper.id)]);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('a pasted picture is attached, but text wins', (tester) async {
      await host(tester);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? clipboardText;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': clipboardText != null};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      clipboard.copiedImage = Uint8List.fromList([137, 80, 78, 71]);
      clipboardText = 'a caption';
      expect(
        await tester.runAsync(
          () => pasteFilesIntoNote(widgetContext, widgetRef, 'n1'),
        ),
        isFalse,
      );
      clipboardText = null;
      expect(
        await tester.runAsync(
          () => pasteFilesIntoNote(widgetContext, widgetRef, 'n1'),
        ),
        isTrue,
      );
      await tester.runAsync(() async {
        final rows = await attachments();
        expect(rows.single.type, AttachmentType.image);
        expect(File(rows.single.path!).readAsBytesSync(), [137, 80, 78, 71]);
      });

      // Nothing but text: Quill pastes it as usual.
      clipboard.copiedImage = null;
      expect(
        await tester.runAsync(
          () => pasteFilesIntoNote(widgetContext, widgetRef, 'n1'),
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
