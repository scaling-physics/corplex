import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/home/adaptive.dart';
import 'package:corplex/features/library/quote_to_note.dart';
import 'package:corplex/features/navigation/nav_target.dart';
import 'package:corplex/features/navigation/panes.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

void main() {
  group('pane state', () {
    test('widths: one fills, several share 520-760, overflow scrolls', () {
      expect(paneWidthFor(1500, 1), 1500);
      expect(paneWidthFor(1200, 2), 600);
      expect(paneWidthFor(3200, 2), paneMaxWidth);
      expect(paneWidthFor(1100, 3), 640);
    });

    test('open after, dedupe, close, mirror and external changes', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(panesProvider.notifier);
      c.read(selectedNoteProvider); // keep alive
      n.replace(0, const NoteTarget('a'));
      expect(c.read(selectedNoteProvider), 'a');
      final first = c.read(panesProvider).notes.panes.first.id;
      n.openAfter(0, first, const NoteTarget('b'));
      n.openAfter(0, first, const NoteTarget('c')); // drops b
      var s = c.read(panesProvider).notes;
      expect(s.panes.map((p) => p.target.key), ['note:a', 'note:c']);
      expect(c.read(selectedNoteProvider), 'c');
      // already open: focus, no duplicate
      n.openAfter(0, s.panes.last.id, const NoteTarget('a'));
      s = c.read(panesProvider).notes;
      expect(s.panes.length, 2);
      expect(c.read(selectedNoteProvider), 'a');
      // closing the focused pane moves focus on
      n.closeFocused(0);
      s = c.read(panesProvider).notes;
      expect(s.panes.map((p) => p.target.key), ['note:c']);
      expect(c.read(selectedNoteProvider), 'c');
      // a list click replaces the whole stack
      n.openAfter(0, s.panes.first.id, const NoteTarget('d'));
      c.read(selectedNoteProvider.notifier).state = 'z';
      s = c.read(panesProvider).notes;
      expect(s.panes.map((p) => p.target.key), ['note:z']);
      // closing the last pane clears the selection
      n.closeFocused(0);
      expect(c.read(selectedNoteProvider), isNull);
      expect(c.read(panesProvider).notes.panes, isEmpty);
      // the Library stack is separate
      n.replace(1, const PaperTarget('p'));
      expect(c.read(selectedPaperProvider), 'p');
      expect(c.read(selectedNoteProvider), isNull);
    });
  });

  group('Mac panes', () {
    late AppDatabase db;

    setUpAll(loadMacFonts);
    setUp(() async {
      EditableText.debugDeterministicCursor = true;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
      for (final (id, title) in [('n1', 'Alpha note'), ('n2', 'Beta note')]) {
        await db
            .into(db.notes)
            .insert(NotesCompanion.insert(id: Value(id), title: Value(title)));
      }
    });
    tearDown(() {
      EditableText.debugDeterministicCursor = false;
      db.close();
    });

    Future<ProviderContainer> pump(WidgetTester tester, Size size) async {
      useMacWindow(tester, size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
            shareIntentSourceProvider.overrideWithValue(
              const NoShareIntentSource(),
            ),
          ],
          child: const CorplexApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha note').first);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(NoteEditorScreen)),
      );
    }

    void openFrom(WidgetTester tester, NavTarget t, {bool inNew = true}) {
      final e = tester.element(find.byType(NoteEditorScreen).first);
      final ref = e as WidgetRef;
      inNew ? openInNewPane(e, ref, t) : openReplacingPanes(e, ref, t);
    }

    for (final name in ['display27', 'dell38']) {
      testWidgets('links open beside, dedupe, close at $name', (tester) async {
        final c = await pump(tester, macWindowSizes[name]!);
        expect(find.byType(NoteEditorScreen), findsOneWidget);
        openFrom(tester, const NoteTarget('n2'));
        await tester.pumpAndSettle();
        expect(find.byType(NoteEditorScreen), findsNWidgets(2));
        expect(c.read(selectedNoteProvider), 'n2');
        expect(tester.takeException(), isNull);
        // The unfocused pane shows a slim header with a close button.
        expect(find.byTooltip('Close pane'), findsOneWidget);
        await macScreenshot(tester, 'panes-$name');
        // Opening n1 again focuses its pane.
        openFrom(tester, const NoteTarget('n1'));
        await tester.pumpAndSettle();
        expect(find.byType(NoteEditorScreen), findsNWidgets(2));
        expect(c.read(selectedNoteProvider), 'n1');
        // A deleted note closes only its own pane.
        await (db.delete(db.notes)..where((x) => x.id.equals('n2'))).go();
        await tester.pumpAndSettle();
        expect(find.byType(NoteEditorScreen), findsOneWidget);
        expect(c.read(selectedNoteProvider), 'n1');
        // Pane editors never become the split reader's quote target.
        expect(c.read(pairedNoteProvider), isNull);
        // Replacing opens one pane.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      }, variant: macOnly);
    }

    testWidgets('close pane and the list replacing the stack', (tester) async {
      final c = await pump(tester, macWindowSizes['dell38']!);
      openFrom(tester, const NoteTarget('n2'));
      await tester.pumpAndSettle();
      c.read(panesProvider.notifier).closeFocused(0);
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      openFrom(tester, const NoteTarget('n2'));
      await tester.pumpAndSettle();
      openFrom(tester, const NoteTarget('n1'), inNew: false);
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      c.read(panesProvider.notifier).closeFocused(0);
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }, variant: macOnly);

    testWidgets('narrow window falls back to one pane', (tester) async {
      final c = await pump(tester, macWindowSizes['laptop13']!);
      openFrom(tester, const NoteTarget('n2'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      expect(c.read(selectedNoteProvider), 'n2');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }, variant: macOnly);
  });
}
