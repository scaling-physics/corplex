import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/navigation/link_peek.dart';
import 'package:corplex/features/navigation/nav_target.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mac_screenshot.dart';

String _delta(List<(String, int?)> lines) => jsonEncode([
  for (final (text, header) in lines) ...[
    {'insert': text},
    {
      'insert': '\n',
      if (header != null) 'attributes': {'header': header},
    },
  ],
]);

void main() {
  late AppDatabase db;
  setUpAll(loadMacFonts);
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    Future<void> note(String id, String title, String content) =>
        db.into(db.notes).insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(title),
            content: Value(content),
          ),
        );
    await note(
      'n1',
      'Hippocampus',
      _delta([
        ('Opening paragraph about place cells.', null),
        ('Methods', 1),
        ('We recorded from CA1.', null),
        ('Results', 1),
        ('Place fields remapped. ^r1', null),
      ]),
    );
    await note('locked', 'Secret', 'corplex-locked:v1:k:abc');
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Grid cells in entorhinal cortex',
            authors: const Value('Hafting, Torkel; Moser, May-Britt'),
            year: const Value(2005),
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> pumpPeek(WidgetTester tester, PeekRequest request) async {
    useMacWindow(tester, const Size(1000, 700));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: LinkPeek(
                request: request,
                child: const Text('the link', key: ValueKey('source')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> hover(WidgetTester tester) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(5, 5));
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('source'))));
    return g;
  }

  Future<void> settleReal(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  final card = find.byKey(const ValueKey('link-peek'));

  testWidgets('a note: title and the start, after the hover delay', (
    tester,
  ) async {
    await pumpPeek(tester, const PeekRequest(NoteTarget('n1')));
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(card, findsNothing); // not yet
    await tester.pump(const Duration(milliseconds: 150));
    await settleReal(tester);
    expect(card, findsOneWidget);
    expect(find.text('Hippocampus'), findsOneWidget);
    expect(find.textContaining('Opening paragraph'), findsOneWidget);
    expect(find.textContaining('CA1'), findsOneWidget);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('a heading shows its section only', (tester) async {
    await pumpPeek(
      tester,
      const PeekRequest(NoteTarget('n1'), heading: 'Methods'),
    );
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleReal(tester);
    expect(find.textContaining('CA1'), findsOneWidget);
    expect(find.textContaining('Opening paragraph'), findsNothing);
    expect(find.textContaining('remapped'), findsNothing);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('a block shows that paragraph, without its marker', (
    tester,
  ) async {
    await pumpPeek(
      tester,
      const PeekRequest(NoteTarget('n1'), block: 'r1'),
    );
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleReal(tester);
    expect(find.textContaining('Place fields remapped.'), findsOneWidget);
    expect(find.textContaining('^r1'), findsNothing);
    expect(find.textContaining('CA1'), findsNothing);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('a paper: title, authors, year and the page', (tester) async {
    await pumpPeek(tester, const PeekRequest(PaperTarget('p1', page: 4)));
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleReal(tester);
    expect(find.text('Grid cells in entorhinal cortex'), findsOneWidget);
    expect(find.textContaining('2005'), findsOneWidget);
    expect(find.textContaining('Torkel Hafting'), findsOneWidget);
    expect(find.textContaining('p. 4'), findsOneWidget);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('a locked note shows its title and "Locked"', (tester) async {
    await pumpPeek(tester, const PeekRequest(NoteTarget('locked')));
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleReal(tester);
    expect(find.text('Secret'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('a missing note says so', (tester) async {
    await pumpPeek(tester, const PeekRequest(NoteTarget('gone')));
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleReal(tester);
    expect(find.text('This note or paper is no longer here'), findsOneWidget);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('leaving closes it; resting on the card keeps it', (
    tester,
  ) async {
    await pumpPeek(tester, const PeekRequest(NoteTarget('n1')));
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleReal(tester);
    expect(card, findsOneWidget);
    // Onto the card: stays past the close delay.
    await g.moveTo(tester.getCenter(card));
    await tester.pump(const Duration(seconds: 1));
    expect(card, findsOneWidget);
    // Off both: closes.
    await g.moveTo(const Offset(900, 650));
    await tester.pump(const Duration(milliseconds: 400));
    expect(card, findsNothing);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('Escape closes it', (tester) async {
    await pumpPeek(tester, const PeekRequest(NoteTarget('n1')));
    final g = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleReal(tester);
    expect(card, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(card, findsNothing);
    await g.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);

  testWidgets('a long-press shows it, a press outside dismisses it', (
    tester,
  ) async {
    await pumpPeek(tester, const PeekRequest(NoteTarget('n1')));
    await tester.longPress(find.byKey(const ValueKey('source')));
    await settleReal(tester);
    expect(card, findsOneWidget);
    await tester.tapAt(const Offset(900, 650)); // outside: dismisses
    await tester.pump();
    expect(card, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: macOnly);
}
