import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/notes/note_content.dart';

import 'support/fake_audio_engine.dart';

Widget _appWithDb(AppDatabase db, {FakeAudioEngine? audio}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(audio ?? FakeAudioEngine()),
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
    // TextField's cursor blink uses a periodic Timer; without this it's
    // still armed when a test ends and trips flutter_test's timer check.
    EditableText.debugDeterministicCursor = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  testWidgets('App launches on Notes tab and can switch to Library', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithDb(db));
    await tester.pumpAndSettle();

    expect(find.text('No notes yet'), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(
      find.text('No notes yet'),
      findsNothing,
      reason: 'Notes tab is offstage',
    );
    expect(find.text('Import PDF'), findsOneWidget);

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
    expect(find.text('Mark'), findsNothing);
    await tester.tap(find.text('Audio overview'));
    await tester.pumpAndSettle();
    expect(audio.loads.single.path, '/device/overview.m4a');
    expect(find.text('Mark'), findsOneWidget);

    // Playback reaches 12:34; mark it.
    audio.emitPosition(const Duration(minutes: 12, seconds: 34));
    await tester.pump();
    await tester.tap(find.text('Mark'));
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
}
