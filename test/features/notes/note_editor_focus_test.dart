import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/notes/note_papers_providers.dart';

import '../../support/fake_audio_engine.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(id: const Value('n1'), title: const Value('T')),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p1'), title: 'Attention'),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  testWidgets('the body keeps focus when the editor rebuilds', (tester) async {
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

    bool bodyFocused() =>
        tester.widget<QuillEditor>(find.byType(QuillEditor)).focusNode.hasFocus;
    bool titleFocused() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byType(TextField),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;

    // Focus the title first, so it is what focus would fall back to.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(titleFocused(), isTrue);

    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    expect(bodyFocused(), isTrue);

    // Anything that rebuilds the screen: here, linking a paper adds a chip.
    await linkPaperToNote(db, noteId: 'n1', paperId: 'p1');
    await tester.pumpAndSettle();
    expect(find.text('Attention'), findsOneWidget);

    expect(bodyFocused(), isTrue, reason: 'still typing in the body');
    expect(titleFocused(), isFalse, reason: 'not bounced to the title');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
