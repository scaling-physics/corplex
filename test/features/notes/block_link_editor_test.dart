import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/block_ids.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/l10n/l10n.dart';

import '../../support/fake_audio_engine.dart';

final _target = jsonEncode([
  {'insert': 'Methods'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'We counted spikes.\n'},
  {'insert': 'Results'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'It worked.\n'},
]);

void main() {
  late AppDatabase db;

  setUp(() {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> addNote(
    String id,
    String title,
    String content, {
    String? aliases,
  }) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(title),
          content: Value(content),
          aliases: Value(aliases),
        ),
      );

  Future<QuillController> open(WidgetTester tester, String noteId) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: NoteEditorScreen(noteId: noteId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<QuillEditor>(find.byType(QuillEditor).first)
        .controller;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Types a string one character at a time, as a keyboard would.
  void type(QuillController c, String text) {
    for (final ch in text.split('')) {
      final at = c.selection.baseOffset;
      c.replaceText(at, 0, ch, TextSelection.collapsed(offset: at + 1));
    }
  }

  testWidgets('a block id shows as a mark; a note embed as a card', (
    tester,
  ) async {
    await addNote('t', 'Target', _target);
    await addNote(
      'h',
      'Host',
      jsonEncode([
        {'insert': 'A claim. ^abc123\n'},
        {
          'insert': {
            noteEmbedType: noteEmbedData(noteLink('t', heading: 'Results')),
          },
        },
        {'insert': '\n'},
      ]),
      aliases: 'Home; Base',
    );
    final c = await open(tester, 'h');
    expect(find.text('¶'), findsOneWidget);
    expect(find.text('Target › Results'), findsOneWidget);
    expect(
      find.textContaining('It worked.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Also: Home, Base'), findsOneWidget);
    // The marker is one character, not text.
    expect(c.document.toPlainText(), 'A claim.￼\n￼\n');
    await close(tester);
  });

  testWidgets('typing ![[ embeds a note on its own line', (tester) async {
    await addNote('t', 'Target', _target);
    await addNote(
      'h',
      'Host',
      jsonEncode([
        {'insert': 'Intro\n'},
      ]),
    );
    final c = await open(tester, 'h');
    c.updateSelection(
      const TextSelection.collapsed(offset: 5),
      ChangeSource.local,
    );
    type(c, '![[');
    await tester.pumpAndSettle();
    expect(find.text('Embed a note…'), findsOneWidget);
    await tester.tap(find.text('Target').last);
    await tester.pumpAndSettle();
    final embeds = [
      for (final o in c.document.toDelta().toJson())
        if (o['insert'] is Map) (o['insert'] as Map).keys.single,
    ];
    expect(embeds, [noteEmbedType]);
    expect(c.document.toPlainText(), isNot(contains('![[')));
    expect(storedFromEditor(c.document), contains('corplex://note/t'));
    await close(tester);
  });

  testWidgets('[[#^ marks a paragraph of this note and links to it', (
    tester,
  ) async {
    await addNote(
      'h',
      'Host',
      jsonEncode([
        {'insert': 'Intro line\nSecond line\n'},
      ]),
    );
    final c = await open(tester, 'h');
    c.updateSelection(
      const TextSelection.collapsed(offset: 22),
      ChangeSource.local,
    );
    type(c, '[[');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '#^');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intro line'));
    await tester.pumpAndSettle();
    final stored = storedFromEditor(c.document);
    final id = RegExp(r'Intro line \^([a-z0-9]{6})')
        .firstMatch(Document.fromJson(jsonDecode(stored) as List).toPlainText())
        ?.group(1);
    expect(id, isNotNull, reason: 'the paragraph got an id in the live editor');
    expect(
      c.document.toDelta().toJson().any(
        (o) =>
            o['insert'] is Map && (o['insert'] as Map)[blockIdEmbedType] == id,
      ),
      isTrue,
    );
    expect(stored, contains(noteLink('h', block: id)));
    await close(tester);
  });

  testWidgets('a note naming another shows under Unlinked mentions', (
    tester,
  ) async {
    await addNote('t', 'Hippocampus', _target);
    await addNote(
      'm',
      'Memory',
      jsonEncode([
        {'insert': 'Replay in the hippocampus matters.\n'},
      ]),
    );
    await open(tester, 't');
    // The index builds in the background.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unlinked mentions (1)'), findsOneWidget);
    await tester.tap(find.text('Unlinked mentions (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final row = await (db.select(
      db.notes,
    )..where((n) => n.id.equals('m'))).getSingle();
    expect(row.content, contains(noteLink('t')));
    expect(find.textContaining('Unlinked mentions'), findsNothing);
    await close(tester);
  });

  testWidgets('tapping a heading link in the same note selects the heading', (
    tester,
  ) async {
    await addNote(
      'h',
      'Host',
      jsonEncode([
        {
          'insert': 'Jump to Results',
          'attributes': {'link': noteLink('h', heading: 'results')},
        },
        {'insert': '\n'},
        {'insert': 'Results'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': 'It worked.\n'},
      ]),
    );
    final c = await open(tester, 'h');
    await tester.tapOnText(find.textRange.ofSubstring('Jump to Results'));
    await tester.pumpAndSettle();
    final sel = c.selection;
    expect(c.document.toPlainText().substring(sel.start, sel.end), 'Results');
    await close(tester);
  });
}
