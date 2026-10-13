import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';

import '../../support/fake_audio_engine.dart';

String _stored(String text) => encodeNoteContent(
  Document.fromJson([
    {'insert': '$text\n'},
  ]),
);

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Principles of Neural Science',
            authors: const Value(
              'Kandel, Eric; Schwartz, James; Jessell, Thomas',
            ),
            year: const Value(2013),
            citekey: const Value('kandel2013'),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<QuillController> open(WidgetTester tester, String content) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('T'),
            content: Value(content),
          ),
        );
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
    return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
  }

  testWidgets('the chip shows the page; "Page…" sets, changes and clears it', (
    tester,
  ) async {
    final controller = await open(tester, _stored('See [@kandel2013] here.'));
    expect(find.text('(Kandel et al., 2013)'), findsOneWidget);

    await tester.longPress(find.text('(Kandel et al., 2013)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '42');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    expect(find.text('(Kandel et al., 2013, p. 42)'), findsOneWidget);
    expect(
      storedFromEditor(controller.document),
      _stored('See [@kandel2013, p. 42] here.'),
    );

    // Change it to a range.
    await tester.longPress(find.text('(Kandel et al., 2013, p. 42)'));
    await tester.pumpAndSettle();
    expect(find.text('Page…'), findsNothing);
    await tester.tap(find.text('Change page'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '3-5');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(find.text('(Kandel et al., 2013, pp. 3–5)'), findsOneWidget);

    // Clear it.
    await tester.longPress(find.text('(Kandel et al., 2013, pp. 3–5)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('(Kandel et al., 2013)'), findsOneWidget);
    expect(
      storedFromEditor(controller.document),
      _stored('See [@kandel2013] here.'),
    );

    // Cancelling changes nothing.
    await tester.longPress(find.text('(Kandel et al., 2013)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('(Kandel et al., 2013)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a stored locator shows on load; chapter label via dropdown', (
    tester,
  ) async {
    final controller = await open(
      tester,
      _stored('See [@kandel2013, 42] here.'),
    );
    expect(find.text('(Kandel et al., 2013, p. 42)'), findsOneWidget);
    // Untouched, the stored marker is exactly what was typed.
    expect(
      storedFromEditor(controller.document),
      _stored('See [@kandel2013, 42] here.'),
    );

    await tester.longPress(find.text('(Kandel et al., 2013, p. 42)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(find.text('(Kandel et al., 2013, chap. 2)'), findsOneWidget);
    expect(
      storedFromEditor(controller.document),
      _stored('See [@kandel2013, chap. 2] here.'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
