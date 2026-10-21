import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/navigation/nav_history.dart';
import 'package:corplex/features/navigation/nav_target.dart';
import 'package:corplex/features/navigation/quick_switcher.dart';
import 'package:corplex/features/navigation/quick_switcher_nav.dart';
import 'package:corplex/features/notes/note_sections.dart' show NoteHeading;
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mac_screenshot.dart';

class _FakeNav implements NoteNavigator {
  final jumps = <String>[];
  final ran = <MenuCommand>[];
  @override
  String get noteId => 'n1';
  @override
  String get title => 'Sleep';
  @override
  List<NoteHeading> headings() => const [
    NoteHeading('Introduction', 1, 0),
    NoteHeading('Methods', 2, 30),
  ];
  @override
  void jumpTo(NoteHeading h) => jumps.add(h.text);
  @override
  bool run(MenuCommand c) {
    ran.add(c);
    return true;
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  SwitcherChoice? picked;
  var returned = false;

  setUpAll(loadMacFonts);
  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    picked = null;
    returned = false;
    Future<void> note(
      String id,
      String title, {
      bool pinned = false,
      String? aliases,
    }) => db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(title),
            pinned: Value(pinned),
            aliases: Value(aliases),
          ),
        );
    await note('n1', 'Sleep replay');
    await note('n2', 'Thesis outline', pinned: true);
    await note('n3', 'Hippocampus', aliases: 'place cells');
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Sleep and memory consolidation',
            authors: const Value('Diekelmann, Susanne'),
            citekey: const Value('diekelmann2010'),
          ),
        );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: const Value('pr1'),
            name: 'Sleep review',
          ),
        );
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    container.dispose();
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await showQuickSwitcher(context, ref);
                  returned = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('switcher-field')), text);
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  testWidgets('opens as a panel with the field focused', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('switcher-field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  }, variant: macOnly);

  testWidgets('empty query shows recents, then pinned', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    final h = container.read(navHistoryProvider.notifier);
    h.visit(const NoteTarget('n3'));
    h.visit(const PaperTarget('p1'));
    h.visit(const NoteTarget('n1')); // the open one: left out
    await open(tester);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Sleep and memory consolidation'), findsOneWidget);
    expect(find.text('Hippocampus'), findsOneWidget);
    expect(find.text('Thesis outline'), findsOneWidget);
    expect(find.text('Sleep replay'), findsNothing);
    // Newest first.
    expect(
      tester.getTopLeft(find.text('Sleep and memory consolidation')).dy,
      lessThan(tester.getTopLeft(find.text('Hippocampus')).dy),
    );
  }, variant: macOnly);

  testWidgets('empty history and nothing pinned: no empty-state crash', (
    tester,
  ) async {
    useMacWindow(tester, const Size(1280, 800));
    await db.delete(db.notes).go();
    await open(tester);
    expect(find.byKey(const ValueKey('switcher-field')), findsOneWidget);
  }, variant: macOnly);

  testWidgets('typing ranks; Return opens the first; arrows move', (
    tester,
  ) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, 'sleep');
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Papers'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    expect(returned, isTrue);
    expect(picked!.item, isNotNull);
    expect(picked!.open, SwitcherOpen.normal);
    // First two results are the title prefixes; one down is the second.
    expect(picked!.item!.title.toLowerCase().startsWith('sleep'), isTrue);
  }, variant: macOnly);

  testWidgets('aliases, authors and citekeys match', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, 'place cells');
    expect(find.text('Hippocampus'), findsOneWidget);
    await type(tester, 'diekelmann2010');
    expect(find.text('Sleep and memory consolidation'), findsOneWidget);
    await type(tester, 'zzzzq');
    expect(find.textContaining('Nothing matches'), findsOneWidget);
  }, variant: macOnly);

  testWidgets('Command+Return asks for a new pane, Option+Return the PDF', (
    tester,
  ) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, 'hippo');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(picked!.open, SwitcherOpen.newPane);
    expect(picked!.item!.id, 'n3');

    returned = false;
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await type(tester, 'consolidation');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(picked!.open, SwitcherOpen.pdf);
    expect(picked!.item!.id, 'p1');
  }, variant: macOnly);

  testWidgets('Escape closes without a choice', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);
    expect(returned, isTrue);
    expect(picked, isNull);
  }, variant: macOnly);

  testWidgets('tapping a row chooses it', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, 'thesis');
    await tester.tap(find.text('Thesis outline'));
    await tester.pumpAndSettle();
    expect(picked!.item!.id, 'n2');
  }, variant: macOnly);

  testWidgets('? shows the prefixes in one line', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, '?');
    expect(find.byKey(const ValueKey('switcher-help')), findsOneWidget);
  }, variant: macOnly);

  testWidgets('# without a note says so', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, '#intro');
    expect(find.textContaining('Open a note'), findsOneWidget);
  }, variant: macOnly);

  testWidgets('# lists the focused note headings and jumps', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    final nav = _FakeNav();
    container.read(noteNavigatorRegistryProvider).register(nav);
    await open(tester);
    await type(tester, '#meth');
    expect(find.text('Methods'), findsOneWidget);
    expect(find.text('Introduction'), findsNothing);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked!.heading!.text, 'Methods');
    expect(picked!.navigator, same(nav));
  }, variant: macOnly);

  testWidgets('> lists commands, note-only ones only with a note', (
    tester,
  ) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, '>');
    expect(find.text("Today's note"), findsOneWidget);
    expect(find.text('Import PDF…'), findsOneWidget);
    expect(find.text('Add bibliography'), findsNothing);
    expect(find.text('Lock note'), findsNothing);
    await type(tester, '>lock');
    expect(find.text('Lock all notes'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked!.command!.command, MenuCommand.lockAllNotes);
  }, variant: macOnly);

  testWidgets('> offers note commands while a note is open', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    container.read(noteNavigatorRegistryProvider).register(_FakeNav());
    await open(tester);
    await type(tester, '>bib');
    expect(find.text('Add bibliography'), findsOneWidget);
  }, variant: macOnly);

  testWidgets('Open project… narrows to projects; Backspace widens', (
    tester,
  ) async {
    useMacWindow(tester, const Size(1280, 800));
    await open(tester);
    await type(tester, '>open proj');
    await key(tester, LogicalKeyboardKey.enter);
    expect(returned, isFalse);
    expect(find.text('Sleep review'), findsOneWidget);
    expect(find.text('Thesis outline'), findsNothing);
    await key(tester, LogicalKeyboardKey.backspace);
    expect(find.text('Thesis outline'), findsOneWidget);
  }, variant: macOnly);

  testWidgets('a bottom sheet on a phone', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    await type(tester, 'hippo');
    await tester.tap(find.text('Hippocampus'));
    await tester.pumpAndSettle();
    expect(picked!.item!.id, 'n3');
  });
}
