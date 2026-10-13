import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/home/adaptive.dart';
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

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    for (final (id, title) in [('n1', 'First note'), ('n2', 'Second note')]) {
      await db
          .into(db.notes)
          .insert(NotesCompanion.insert(id: Value(id), title: Value(title)));
    }
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> show(WidgetTester tester, Size logical) async {
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(_NoShares()),
        ],
        child: const CorplexApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  test('layout thresholds', () {
    expect(homeLayoutFor(390), HomeLayout.compact); // iPhone
    expect(homeLayoutFor(744), HomeLayout.medium); // iPad mini portrait
    expect(homeLayoutFor(834), HomeLayout.medium); // iPad Pro 11" portrait
    expect(homeLayoutFor(1024), HomeLayout.expanded); // 13" portrait
    expect(homeLayoutFor(1194), HomeLayout.expanded); // 11" landscape
    expect(readablePadding(400), 24);
    expect(readablePadding(1000), 140);
  });

  testWidgets('a phone keeps the bottom tabs', (tester) async {
    await show(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await dispose(tester);
  });

  testWidgets('iPad portrait: a rail, and lists at a readable width', (
    tester,
  ) async {
    await show(tester, const Size(834, 1194));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final card = tester.getRect(find.text('First note'));
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('First note'),
              matching: find.byType(Card),
            ),
          )
          .width,
      lessThanOrEqualTo(readableWidth),
    );
    expect(card.left, greaterThan(80), reason: 'right of the rail');

    // Opening a note is still a page here.
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Your library is empty'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('iPad landscape: list and note side by side', (tester) async {
    await show(tester, const Size(1194, 834));
    expect(find.text('Pick a note, or start a new one.'), findsOneWidget);

    await tester.tap(find.text('Second note'));
    await tester.pumpAndSettle();
    // The editor is beside the list, with no back arrow…
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('First note'), findsOneWidget, reason: 'list still there');
    final editor = tester.getRect(find.byType(NoteEditorScreen));
    expect(editor.left, greaterThan(400));

    // …and switching notes swaps the pane.
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NoteEditorScreen>(find.byType(NoteEditorScreen)).noteId,
      'n1',
    );

    // New note opens in the pane too.
    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NoteEditorScreen>(find.byType(NoteEditorScreen)).noteId,
      isNot(anyOf('n1', 'n2')),
    );
    await dispose(tester);
  });

  testWidgets('trashing the open note clears the pane, not the app', (
    tester,
  ) async {
    await show(tester, const Size(1194, 834));
    await tester.tap(find.text('Second note'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Move to trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to trash'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget, reason: 'still home');
    expect(find.text('Pick a note, or start a new one.'), findsOneWidget);
    expect(find.text('Second note'), findsNothing);
    await dispose(tester);
  });
}
