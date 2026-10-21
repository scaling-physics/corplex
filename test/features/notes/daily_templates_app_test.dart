import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/daily_notes.dart';
import 'package:corplex/features/notes/daily_settings.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/quick_action_source.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';

class _NoShares implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> initial() async => const [];
  @override
  Stream<List<SharedMediaFile>> get stream => const Stream.empty();
  @override
  Future<void> reset() async {}
}

class _FakeQuick implements QuickActionSource {
  _FakeQuick(this.launch);
  final String? launch;
  void Function(String)? handler;

  @override
  Future<void> start(void Function(String type) onAction) async {
    handler = onAction;
    if (launch != null) onAction(launch!);
  }
}

void main() {
  late AppDatabase db;

  setUpAll(() => initializeDateFormatting('en'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> pumpApp(WidgetTester tester, {_FakeQuick? quick}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(_NoShares()),
          quickActionSourceProvider.overrideWithValue(
            quick ?? _FakeQuick(null),
          ),
        ],
        child: const CorplexApp(),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> addTemplate({String title = 'Meeting'}) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('tpl'),
            title: Value(title),
            content: Value(
              encodeNoteContent(
                Document()..insert(0, 'Agenda for {{date:YYYY}}'),
              ),
            ),
            isTemplate: const Value(true),
          ),
        );
  }

  testWidgets('the Today shortcut opens today\'s note, once', (tester) async {
    final quick = _FakeQuick(quickTodaysNote);
    await pumpApp(tester, quick: quick);
    await settle(tester);
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    var notes = await db.select(db.notes).get();
    expect(notes, hasLength(1));
    expect(notes.single.dailyDate, dailyKey(DateTime.now()));

    // Again while running: the same note, not another.
    await tester.pageBack();
    await settle(tester);
    quick.handler!(quickTodaysNote);
    await settle(tester);
    notes = await db.select(db.notes).get();
    expect(notes, hasLength(1));
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('today\'s note starts from the daily template and folder', (
    tester,
  ) async {
    await addTemplate();
    await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(id: const Value('f'), name: 'Log'));
    SharedPreferences.setMockInitialValues({
      'daily.templateId': 'tpl',
      'daily.folderId': 'f',
    });
    await pumpApp(tester, quick: _FakeQuick(quickTodaysNote));
    await settle(tester);
    final daily = (await db.select(db.notes).get()).singleWhere(
      (n) => n.dailyDate != null,
    );
    expect(daily.folderId, 'f');
    expect(daily.isTemplate, isFalse);
    expect(daily.content, contains('Agenda for ${DateTime.now().year}'));
    await dispose(tester);
  });

  testWidgets('long-pressing New note offers Today and the templates', (
    tester,
  ) async {
    await addTemplate();
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: const Value('t'), name: 'mtg'));
    await db
        .into(db.noteTags)
        .insert(NoteTagsCompanion.insert(noteId: 'tpl', tagId: 't'));
    await pumpApp(tester);
    await settle(tester);

    // Nothing on the default screen: the template isn't in the list.
    expect(find.text('Meeting'), findsNothing);

    await tester.longPress(find.text('New note'));
    await settle(tester);
    expect(find.text('Today\'s note'), findsOneWidget);
    expect(find.text('Literature note'), findsOneWidget);
    expect(find.text('Meeting'), findsOneWidget);

    await tester.tap(find.text('Meeting'));
    await settle(tester);
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    final notes = await db.select(db.notes).get();
    expect(notes, hasLength(2));
    final made = notes.singleWhere((n) => !n.isTemplate);
    expect(made.title, '');
    expect(made.content, contains('Agenda for ${DateTime.now().year}'));
    final tags = await db.select(db.noteTags).get();
    expect(tags.map((t) => '${t.noteId}:${t.tagId}'), contains('${made.id}:t'));
    await dispose(tester);
  });

  testWidgets('the long-press sheet works with no templates', (tester) async {
    await pumpApp(tester);
    await settle(tester);
    await tester.longPress(find.text('New note'));
    await settle(tester);
    await tester.tap(find.text('Today\'s note'));
    await settle(tester);
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect((await db.select(db.notes).get()).single.dailyDate, isNotNull);
    await dispose(tester);
  });

  testWidgets('Templates chip appears once a template exists', (tester) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            title: const Value('Ordinary'),
          ),
        );
    await pumpApp(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('templates-chip')), findsNothing);

    await addTemplate();
    await settle(tester);
    expect(find.byKey(const ValueKey('templates-chip')), findsOneWidget);
    expect(find.text('Meeting'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('templates-chip')));
    await settle(tester);
    expect(find.text('Meeting'), findsOneWidget);
    expect(find.text('Ordinary'), findsNothing);

    // The last template stops being one: back to all notes, chip gone.
    await db
        .update(db.notes)
        .write(const NotesCompanion(isTemplate: Value(false)));
    await settle(tester);
    expect(find.byKey(const ValueKey('templates-chip')), findsNothing);
    expect(find.text('Ordinary'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('note menu: use as template, and day navigation', (tester) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('old'),
            title: const Value('Earlier day'),
            dailyDate: const Value('2020-01-01'),
          ),
        );
    await pumpApp(tester, quick: _FakeQuick(quickTodaysNote));
    // Tall, so the long note menu fits without scrolling.
    tester.view.physicalSize = const Size(1080, 4800);
    await settle(tester);
    expect(find.byType(NoteEditorScreen), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Use as template'), findsOneWidget);
    expect(find.text('Previous day\'s note'), findsOneWidget);
    await tester.tap(find.text('Previous day\'s note'));
    await settle(tester);
    expect(
      tester.widget<NoteEditorScreen>(find.byType(NoteEditorScreen)).noteId,
      'old',
    );

    // Next goes back; there is nothing after today.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next day\'s note'));
    await settle(tester);
    expect(
      tester.widget<NoteEditorScreen>(find.byType(NoteEditorScreen)).noteId,
      isNot('old'),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next day\'s note'));
    await settle(tester);
    expect(find.text('No later daily note'), findsOneWidget);

    // Use as template.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use as template'));
    await settle(tester);
    final today = await findDailyNote(db, dailyKey(DateTime.now()));
    final row = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(today!))).getSingle();
    expect(row.isTemplate, isTrue);
    // Still open.
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    await dispose(tester);
  });

  test('daily settings persist per device', () async {
    SharedPreferences.setMockInitialValues({});
    final s = DailyNoteSettings();
    await s.setTemplate('a');
    await s.setFolder('b');
    final loaded = await DailyNoteSettings.load();
    expect(loaded.templateId, 'a');
    expect(loaded.folderId, 'b');
    await s.setTemplate(null);
    expect((await DailyNoteSettings.load()).templateId, isNull);
  });
}
