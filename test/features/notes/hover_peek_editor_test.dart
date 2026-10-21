import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/navigation/link_peek.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/l10n/l10n.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

void main() {
  late AppDatabase db;

  setUpAll(loadMacFonts);
  setUp(() {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  testWidgets('hovering a note link in the real editor shows the card', (
    tester,
  ) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('t'),
            title: const Value('Target note'),
            content: Value(
              jsonEncode([
                {'insert': 'The target body text.\n'},
              ]),
            ),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('h'),
            title: const Value('Host'),
            content: Value(
              jsonEncode([
                {'insert': 'See '},
                {
                  'insert': 'Target note',
                  'attributes': {'link': noteLink('t')},
                },
                {'insert': ' for more.\n'},
              ]),
            ),
          ),
        );
    tester.view.physicalSize = const Size(1400, 900);
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
          home: const NoteEditorScreen(noteId: 'h'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Where the link text is on screen.
    final editor = tester.state<QuillRawEditorState>(
      find.byType(QuillRawEditor),
    );
    final render = editor.renderEditor;
    final linkStart = 'See '.length;
    final box = render.getEndpointsForSelection(
      TextSelection(baseOffset: linkStart, extentOffset: linkStart + 11),
    );
    final y = render.localToGlobal(box.first.point).dy - 8;
    final x = render.localToGlobal(box.first.point).dx + 20;

    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(5, 5));
    await g.moveTo(Offset(x, y));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinkPeekCard), findsOneWidget);
    expect(find.textContaining('The target body text'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, variant: macOnly);
}
