import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/quote_to_note.dart';
import 'package:corplex/features/library/split_reader.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
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

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention',
            pdfPath: const Value('/x.pdf'),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Widget scope(Widget child) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      shareIntentSourceProvider.overrideWithValue(_NoShares()),
    ],
    child: child,
  );

  test(
    'reading beside a note reuses the latest linked note, else makes one',
    () async {
      final paper = await (db.select(db.papers)).getSingle();
      final made = await noteForReading(db, paper);
      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(made))).getSingle();
      expect(note.title, 'Notes on Attention');
      expect(await db.select(db.notePaperRefs).get(), hasLength(1));

      // A second call finds it rather than creating another.
      expect(await noteForReading(db, paper), made);
      expect(await db.select(db.notes).get(), hasLength(1));
    },
  );

  testWidgets('a quote from the reader goes straight into the open note', (
    tester,
  ) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Mine'),
          ),
        );
    final handle = NoteEditorHandle();
    late WidgetRef ref;
    late BuildContext ctx;

    await tester.pumpWidget(
      scope(
        MaterialApp(
          localizationsDelegates: const [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Column(
            children: [
              Expanded(
                child: NoteEditorScreen(
                  noteId: 'n1',
                  handle: handle,
                  embedded: true,
                ),
              ),
              Consumer(
                builder: (context, r, _) {
                  ref = r;
                  ctx = context;
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      handle.appendQuote,
      isNotNull,
      reason: 'the editor registered itself',
    );
    expect(
      find.byType(BackButton),
      findsNothing,
      reason: 'embedded: the reader owns back',
    );

    ref.read(pairedNoteProvider.notifier).state = handle;
    final highlight = Highlight(
      id: 'h',
      paperId: 'p1',
      pageNumber: 4,
      quote: 'self-attention',
      rectsJson: '[]',
      colorHex: 'F2D66B',
      comment: 'key idea',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    // Real DB work never completes under the fake clock.
    await tester.runAsync(() => showQuoteToNoteSheet(ctx, ref, highlight));
    await tester.pump();

    expect(find.text('Added to your note'), findsOneWidget);
    expect(
      find.text('New note'),
      findsNothing,
      reason: 'no "which note?" sheet',
    );
    // The open editor shows the quote, with its page reference and the
    // reader's comment (persisting is the editor's ordinary autosave).
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('self-attention', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('p. 4', findRichText: true), findsOneWidget);
    expect(find.textContaining('key idea', findRichText: true), findsOneWidget);
    await tester.runAsync(() async {
      expect(await db.select(db.notes).get(), hasLength(1));
      expect(
        await db.select(db.notePaperRefs).get(),
        hasLength(1),
        reason: 'linked to the paper',
      );
    });

    await _disposeTree(tester);
    expect(handle.appendQuote, isNull, reason: 'unregistered on dispose');
  });

  testWidgets(
    'keyboard shortcuts: Ctrl+2 goes to Library, Ctrl+1 back, Ctrl+N starts a note',
    (tester) async {
      await tester.pumpWidget(scope(const CorplexApp()));
      await tester.pumpAndSettle();
      expect(find.text('No notes yet'), findsOneWidget);

      Future<void> chord(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await chord(LogicalKeyboardKey.digit2);
      expect(
        find.text('Attention'),
        findsOneWidget,
        reason: 'the library lists the paper',
      );
      await chord(LogicalKeyboardKey.digit1);
      expect(find.text('No notes yet'), findsOneWidget);

      await chord(LogicalKeyboardKey.keyN);
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      expect(await db.select(db.notes).get(), hasLength(1));

      await _disposeTree(tester);
    },
  );
}
