import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'support/fake_audio_engine.dart';

class _NoShares implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> initial() async => const [];

  @override
  Stream<List<SharedMediaFile>> get stream => const Stream.empty();

  @override
  Future<void> reset() async {}
}

Widget _appWithDb(AppDatabase db, {FakeAudioEngine? audio}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(audio ?? FakeAudioEngine()),
      // The real share plugin has no implementation under `flutter test`.
      shareIntentSourceProvider.overrideWithValue(_NoShares()),
    ],
    child: const CorplexApp(),
  );
}

/// Disposing a drift stream query schedules a zero-duration Timer to mark
/// itself closed. If left to flutter_test's automatic teardown, that timer
/// has no chance to fire before the framework's `!timersPending` check
/// runs. Tearing the tree down ourselves and pumping once first flushes it.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // A duration, even a small one, is required to make FakeAsync actually
  // elapse and fire the zero-duration timer scheduled during disposal.
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase db;

  setUp(() {
    // These are phone-layout tests (bottom tabs, "New note" button); the
    // default 800×600 test screen would get the tablet layout.
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3;
    // TextField's cursor blink uses a periodic Timer; without this it's
    // still armed when a test ends and trips flutter_test's timer check.
    EditableText.debugDeterministicCursor = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  testWidgets('App launches on Notes tab and can switch to Library', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();

    // A first launch: the welcome steps, not a blank page.
    expect(find.text('Welcome to Corplex'), findsOneWidget);
    expect(find.text('Import your first paper'), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Corplex'), findsOneWidget);
    expect(find.text('Import PDF'), findsOneWidget);

    // Once anything exists, the welcome goes and the usual empty states
    // take over.
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(title: const Value('First')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Corplex'), findsNothing);
    expect(find.text('Your library is empty'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('creating a note from the FAB shows it in the list', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'My first paper notes',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('My first paper notes'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('opening a note without editing it does not touch it', (
    tester,
  ) async {
    final stamp = DateTime(2025, 1, 2, 3, 4, 5);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Old note'),
            updatedAt: Value(stamp),
          ),
        );
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Old note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first); // cursor, no typing
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.pageBack();
    await tester.pumpAndSettle();

    final note = await db.select(db.notes).getSingle();
    expect(note.updatedAt, stamp);
    await _disposeTree(tester);
  });

  testWidgets('an edit made just before leaving is still saved', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Quick thought');
    // Tear the editor down at once, well inside the autosave debounce (a
    // back navigation's animation would outlast it and hide the bug).
    await _disposeTree(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    expect((await db.select(db.notes).getSingle()).title, 'Quick thought');
  });

  testWidgets('listening to audio and marking timestamps in a note', (
    tester,
  ) async {
    final audio = FakeAudioEngine();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Lecture notes'),
          ),
        );
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: const Value('rec1'),
            noteId: const Value('n1'),
            type: AttachmentType.podcast,
            path: const Value('/device/overview.m4a'),
            title: const Value('Audio overview'),
          ),
        );
    await tester.pumpWidget(_appWithDb(db, audio: audio));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture notes'));
    await tester.pumpAndSettle();

    // No player until something is played.
    expect(find.byTooltip('Mark'), findsNothing);
    await tester.tap(find.text('Audio overview'));
    await tester.pumpAndSettle();
    expect(audio.loads.single.path, '/device/overview.m4a');
    expect(find.byTooltip('Mark'), findsOneWidget);

    // Playback reaches 12:34; mark it.
    audio.emitPosition(const Duration(minutes: 12, seconds: 34));
    await tester.pump();
    await tester.tap(find.byTooltip('Mark'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final note = await db.select(db.notes).getSingle();
    expect(note.content, contains('▸ 12:34'));
    expect(note.content, contains('corplex://audio/rec1?t=754'));

    // Jump elsewhere, then tap the timestamp to come back to it.
    audio.emitPosition(const Duration(minutes: 20));
    audio.seeks.clear();
    await tester.pump();
    // Tap on the timestamp's own characters (the paragraph is full width).
    final stamp = find.textContaining('▸ 12:34', findRichText: true);
    await tester.tapAt(tester.getTopLeft(stamp.first) + const Offset(12, 10));
    await tester.pumpAndSettle();
    expect(audio.seeks, [const Duration(minutes: 12, seconds: 34)]);

    await _disposeTree(tester);
  });

  testWidgets('the player sits at the bottom of a paper, under its content', (
    tester,
  ) async {
    final audio = FakeAudioEngine();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
          ),
        );
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            paperId: const Value('p1'),
            type: AttachmentType.podcast,
            path: const Value('/device/overview.m4a'),
            title: const Value('Audio overview'),
          ),
        );
    await tester.pumpWidget(_appWithDb(db, audio: audio));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attention Is All You Need'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio overview'));
    await tester.pumpAndSettle();

    // As a page's bottom bar the player once grew to the screen's height,
    // hiding the whole page behind it.
    expect(find.text('Attention Is All You Need'), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bar = tester.getRect(find.byTooltip('Close player'));
    expect(bar.top, greaterThan(screen.height * 0.75));

    await _disposeTree(tester);
  });

  testWidgets('drawing a sketch in a note with a stylus', (tester) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Diagram'),
            content: const Value('[{"insert":"Before\\n"}]'),
          ),
        );
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagram'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Draw'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    final canvas = find.byType(InkCanvas);
    final start = tester.getTopLeft(canvas) + const Offset(40, 40);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(start + Offset(i * 25.0, i * 5.0));
    }
    await g.up();
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Back in the note, the drawing shows and is saved in its content.
    expect(find.textContaining('Before', findRichText: true), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    final saved = (await db.select(db.notes).getSingle()).content;
    expect(saved, contains('"sketch"'));
    final data =
        (jsonDecode(saved) as List)
                .map((op) => (op as Map)['insert'])
                .whereType<Map>()
                .single['sketch']
            as String;
    expect(Sketch.decode(data).strokes, hasLength(1));
    expect(notePlainTextPreview(saved), 'Before');

    await _disposeTree(tester);
  });

  testWidgets('tapping Draw and leaving without drawing adds nothing', (
    tester,
  ) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Plain'),
            content: const Value('[{"insert":"Text\\n"}]'),
          ),
        );
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final saved = (await db.select(db.notes).getSingle()).content;
    expect(saved, isNot(contains('sketch')));
    await _disposeTree(tester);
  });

  testWidgets('typing [[ links another note, which then shows a backlink', (
    tester,
  ) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('target'),
            title: const Value('Transformers'),
            updatedAt: Value(DateTime(2025)),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('source'),
            title: const Value('Reading list'),
            content: const Value('[{"insert":"See \\n"}]'),
          ),
        );
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading list'));
    await tester.pumpAndSettle();

    // Type "[[" at the end of "See ".
    final editor = find.byType(QuillEditor);
    final controller = tester.widget<QuillEditor>(editor).controller;
    controller.updateSelection(
      const TextSelection.collapsed(offset: 4),
      ChangeSource.local,
    );
    controller.replaceText(4, 0, '[', null);
    controller.replaceText(5, 0, '[', null);
    await tester.pumpAndSettle();

    // The picker opened; pick the target.
    await tester.enterText(find.byType(TextField).last, 'Trans');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transformers').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final saved = (await (db.select(
      db.notes,
    )..where((n) => n.id.equals('source'))).getSingle()).content;
    expect(saved, contains('corplex://note/target'));
    expect(saved, isNot(contains('[[')));

    // Open the target: it lists the source as linking to it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transformers'));
    await tester.pumpAndSettle();
    expect(find.text('Linked from'), findsOneWidget);
    expect(find.text('Reading list'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('reading status: chips on the paper, a filter once one is set', (
    tester,
  ) async {
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p1'), title: 'Attention'),
        );
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('p2'), title: 'BERT'));
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    // No status anywhere: no filter row.
    expect(find.widgetWithText(ChoiceChip, 'To read'), findsNothing);

    await tester.tap(find.text('Attention'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Reading'));
    await tester.pumpAndSettle();
    expect(
      (await (db.select(
        db.papers,
      )..where((p) => p.id.equals('p1'))).getSingle()).readingStatus,
      ReadingStatus.reading,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    // Now the filter row exists; choose "Reading" to hide BERT.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Reading'));
    await tester.pumpAndSettle();
    expect(find.text('Attention'), findsOneWidget);
    expect(find.text('BERT'), findsNothing);

    // Tapping the status again on the paper clears it.
    await tester.tap(find.text('Attention'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Reading'));
    await tester.pumpAndSettle();
    expect(
      (await (db.select(
        db.papers,
      )..where((p) => p.id.equals('p1'))).getSingle()).readingStatus,
      isNull,
    );

    await _disposeTree(tester);
  });

  testWidgets('paper details are editable and saved', (tester) async {
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p1'), title: 'Attention'),
        );
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attention'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Year'), '2017');
    await tester.enterText(
      find.widgetWithText(TextField, 'Journal or conference'),
      'NeurIPS',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    final paper = await db.select(db.papers).getSingle();
    expect(paper.year, 2017);
    expect(paper.venue, 'NeurIPS');
    await _disposeTree(tester);
  });

  testWidgets(
    'outside changes update untouched fields, not ones being edited',
    (tester) async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'upload_final',
            ),
          );
      await tester.pumpWidget(_appWithDb(db));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('upload_final'));
      await tester.pumpAndSettle();

      // The reader starts typing an author…
      await tester.enterText(
        find.widgetWithText(TextField, 'Authors'),
        'Me, Myself',
      );
      // …while a background lookup fills in the rest.
      await (db.update(db.papers)..where((p) => p.id.equals('p1'))).write(
        const PapersCompanion(
          title: Value('Attention Is All You Need'),
          authors: Value('Vaswani, Ashish'),
          venue: Value('NeurIPS'),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(
        find.text('Attention Is All You Need'),
        findsOneWidget,
        reason: 'untouched: updated',
      );
      expect(find.text('NeurIPS'), findsOneWidget);
      expect(
        find.text('Me, Myself'),
        findsOneWidget,
        reason: 'being edited: kept',
      );
      expect((await db.select(db.papers).getSingle()).authors, 'Me, Myself');

      await _disposeTree(tester);
    },
  );

  testWidgets(
    'searching finds a note, a paper and a highlight, and opens them',
    (tester) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Lecture 3'),
              content: const Value(
                '[{"insert":"backpropagation through time\\n"}]',
              ),
            ),
          );
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'Backpropagation applied to zip codes',
            ),
          );
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              paperId: 'p1',
              pageNumber: 2,
              quote: 'Gradient descent via backpropagation',
              rectsJson: '[]',
            ),
          );
      await tester.pumpWidget(_appWithDb(db));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search everything'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'backprop');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Papers'), findsOneWidget);
      expect(find.text('Highlights'), findsOneWidget);
      expect(find.text('Lecture 3'), findsOneWidget);

      await tester.tap(find.text('Lecture 3'));
      await tester.pumpAndSettle();
      expect(find.text('Lecture 3'), findsWidgets); // the editor's title field

      await _disposeTree(tester);
    },
  );

  testWidgets('a search with no matches says so', (tester) async {
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('projects: hidden until made, then filter notes and papers', (
    tester,
  ) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('In project'),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n2'),
            title: const Value('Elsewhere'),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Paper in project',
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p2'), title: 'Other paper'),
        );
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();

    // Nothing project-related on screen until one exists.
    expect(find.byIcon(Icons.folder_special_outlined), findsNothing);

    // Make one from the paper's screen.
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paper in project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New project'),
      'Thesis',
    );
    await tester.tap(find.byTooltip('Create and add'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Thesis'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Thesis'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The Library now has a Thesis chip that filters papers.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Thesis'));
    await tester.pumpAndSettle();
    expect(find.text('Paper in project'), findsOneWidget);
    expect(find.text('Other paper'), findsNothing);

    // Put a note in the project from the note editor, then filter notes.
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In project'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Thesis'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Thesis'));
    await tester.pumpAndSettle();
    expect(find.text('In project'), findsOneWidget);
    expect(find.text('Elsewhere'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets(
    'swiping a note away moves it to the trash, and Undo brings it back',
    (tester) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Draft'),
            ),
          );
      await tester.pumpWidget(_appWithDb(db));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Draft'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Draft'), findsNothing);
      expect(find.textContaining('moved to trash'), findsOneWidget);
      expect(await db.select(db.notes).get(), isEmpty);
      expect(await db.select(db.trashItems).get(), hasLength(1));

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Draft'), findsOneWidget);
      expect(await db.select(db.notes).get(), hasLength(1));
      expect(await db.select(db.trashItems).get(), isEmpty);

      await _disposeTree(tester);
    },
  );

  testWidgets(
    'a paper can be trashed from its screen and restored from the Trash',
    (tester) async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'Doomed paper',
            ),
          );
      await tester.pumpWidget(_appWithDb(db));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doomed paper'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Move to trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to trash'));
      await tester.pumpAndSettle();

      // Back on the library, which no longer lists it.
      // Nothing left at all: back to the first-launch welcome.
      expect(find.text('Welcome to Corplex'), findsOneWidget);

      // Account sheet -> Trash -> Restore.
      await tester.tap(find.byTooltip('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('1 item'), findsOneWidget);
      await tester.tap(find.text('Trash'));
      await tester.pumpAndSettle();
      expect(find.text('Doomed paper'), findsOneWidget);
      expect(find.textContaining('days left'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.text('Trash is empty'), findsOneWidget);
      expect(await db.select(db.papers).get(), hasLength(1));

      await _disposeTree(tester);
    },
  );

  testWidgets(
    'the account sheet works signed out: sign in, trash, backup, restore',
    (tester) async {
      await tester.pumpWidget(_appWithDb(db));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Trash'), findsOneWidget);
      expect(find.text('Back up to a file'), findsOneWidget);
      expect(find.text('Restore from a backup'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);

      await _disposeTree(tester);
    },
  );

  testWidgets(
    'trashing from the note editor leaves the editor and can be undone',
    (tester) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Editing this'),
            ),
          );
      await tester.pumpWidget(_appWithDb(db));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editing this'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Move to trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to trash'));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsWidgets); // back on the list
      expect(await db.select(db.notes).get(), isEmpty);
      // The editor's autosave must not have resurrected the note.
      await tester.pump(const Duration(seconds: 1));
      expect(await db.select(db.notes).get(), isEmpty);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await db.select(db.notes).get(), hasLength(1));
      await _disposeTree(tester);
    },
  );
}
