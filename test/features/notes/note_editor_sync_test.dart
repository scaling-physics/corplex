import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';

import '../../support/fake_audio_engine.dart';

String _body(List<String> paragraphs) => jsonEncode([
  for (final p in paragraphs) {'insert': '$p\n'},
]);

/// A note open in the editor while a sync changes it underneath (as on an
/// iPad, where the open note stays in the side pane).
void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Review'),
            content: Value(_body(['Intro'])),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: NoteEditorScreen(noteId: 'n1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  QuillController controller(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  Future<Note> stored() =>
      (db.select(db.notes)..where((n) => n.id.equals('n1'))).getSingle();

  /// What a sync does: write the row behind the editor's back.
  Future<void> syncWrites({String? title, List<String>? body}) =>
      (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
        NotesCompanion(
          title: title == null ? const Value.absent() : Value(title),
          content: body == null ? const Value.absent() : Value(_body(body)),
        ),
      );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('a synced change shows up and is not saved over', (tester) async {
    await open(tester);
    await syncWrites(title: 'Literature review', body: ['Intro', 'From iPad']);
    await tester.pumpAndSettle();

    expect(controller(tester).document.toPlainText(), 'Intro\nFrom iPad\n');
    expect(find.text('Literature review'), findsOneWidget);

    // Typing afterwards builds on the synced text.
    controller(tester)
        .replaceText(0, 0, 'Note: ', const TextSelection.collapsed(offset: 6));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final note = await stored();
    expect(
      decodeNoteContent(note.content).toPlainText(),
      'Note: Intro\nFrom iPad\n',
    );
    expect(note.title, 'Literature review');
    await close(tester);
  });

  testWidgets('text typed but not yet saved is merged with the sync', (
    tester,
  ) async {
    await open(tester);
    // Typed, and the autosave hasn't fired yet...
    controller(tester).replaceText(
      5,
      0,
      ', sharpened',
      const TextSelection.collapsed(offset: 16),
    );
    // ...when a sync brings another device's paragraph.
    await syncWrites(body: ['Intro', 'From iPad']);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    const both = 'Intro, sharpened\nFrom iPad\n';
    expect(controller(tester).document.toPlainText(), both);
    expect(decodeNoteContent((await stored()).content).toPlainText(), both);
    expect(
      controller(tester).selection.baseOffset,
      16,
      reason: 'the cursor stays where you were typing',
    );
    await close(tester);
  });
}
