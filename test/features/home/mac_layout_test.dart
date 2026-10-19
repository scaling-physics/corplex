import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/home/mac_sidebar.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:corplex/features/trash/trash_screen.dart';
import 'package:corplex/features/search/search_screen.dart';
import 'package:corplex/features/attachments/attachments_browser.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

import 'package:corplex/features/capture/quick_capture.dart';

class _FakeWindow implements MacWindow {
  final commands = StreamController<MenuCommand>.broadcast();
  final captureController = StreamController<QuickCapture>.broadcast();
  final hotKeyCalls = <bool>[];
  @override
  Stream<QuickCapture> get captures => captureController.stream;
  @override
  Future<bool> setQuickNoteHotKey(bool enabled) async {
    hotKeyCalls.add(enabled);
    return enabled;
  }

  final _full = ValueNotifier(false);
  @override
  Stream<MenuCommand> get menuCommands => commands.stream;
  @override
  ValueListenable<bool> get fullScreen => _full;
  final _band = ValueNotifier(macToolbarHeight);
  final toolbarCalls = <bool>[];
  @override
  ValueListenable<double> get titleBand => _band;
  @override
  Future<void> setToolbar(bool visible) async {
    toolbarCalls.add(visible);
    _band.value = visible ? macToolbarHeight : macTitleBarHeight;
  }

  @override
  Future<void> startDrag() async {}
  @override
  Future<void> zoom() async {}
  final printed = <(Uint8List, String)>[];
  @override
  Future<bool> printPdf(Uint8List pdf, String title) async {
    printed.add((pdf, title));
    return true;
  }
}

void main() {
  late AppDatabase db;
  late _FakeWindow window;

  setUpAll(loadMacFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    window = _FakeWindow();
    for (final (id, title) in [('n1', 'First note'), ('n2', 'Second note')]) {
      await db
          .into(db.notes)
          .insert(NotesCompanion.insert(id: Value(id), title: Value(title)));
    }
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    window.commands.close();
    db.close();
  });

  Future<void> show(WidgetTester tester, Size size) async {
    useMacWindow(tester, size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(
            const NoShareIntentSource(),
          ),
          macWindowProvider.overrideWithValue(window),
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

  Future<void> send(WidgetTester tester, MenuCommand c) async {
    window.commands.add(c);
    await tester.pumpAndSettle();
  }

  for (final MapEntry(key: name, value: size) in macWindowSizes.entries) {
    testWidgets('sidebar instead of rail or FAB at $name', (tester) async {
      await show(tester, size);
      expect(find.byKey(const ValueKey('mac-sidebar')), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
      // One toolbar row, as in Notes: the controls sit in the title bar
      // band, level with the traffic lights and clear of them.
      final sidebar = tester.getRect(find.byKey(const ValueKey('mac-sidebar')));
      final primary = tester.getRect(
        find.byKey(const ValueKey('mac-primary-action')),
      );
      final newFolder = tester.getRect(
        find.byKey(const ValueKey('mac-new-folder')),
      );
      final search = tester.getRect(
        find.byKey(const ValueKey('mac-toolbar-search')),
      );
      for (final r in [primary, newFolder, search]) {
        expect(r.center.dy, closeTo(macToolbarHeight / 2, 1));
      }
      expect(newFolder.left, greaterThanOrEqualTo(macTrafficLightsWidth));
      expect(primary.left, greaterThanOrEqualTo(sidebar.right));
      expect(sidebar.width, macSidebarWidth);
      // Search and Attachments are no longer sidebar rows.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mac-sidebar')),
          matching: find.text('Search'),
        ),
        findsNothing,
      );
      expect(find.text('Attachments'), findsNothing);
      await macScreenshot(tester, 'shell-$name');
      await dispose(tester);
    }, variant: macOnly);
  }

  testWidgets('menu commands drive the shell', (tester) async {
    await show(tester, macWindowSizes['laptop13']!);
    expect(find.text('Pick a note, or start a new one.'), findsOneWidget);

    await send(tester, MenuCommand.showLibrary);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.byTooltip('Import PDF (\u2318O)'), findsOneWidget);

    await send(tester, MenuCommand.showNotes);
    expect(find.text('First note'), findsOneWidget);

    await send(tester, MenuCommand.newNote);
    expect(find.byType(NoteEditorScreen), findsOneWidget);

    await send(tester, MenuCommand.toggleSidebar);
    expect(find.byKey(const ValueKey('mac-sidebar')), findsNothing);
    await send(tester, MenuCommand.toggleSidebar);
    expect(find.byKey(const ValueKey('mac-sidebar')), findsOneWidget);

    await send(tester, MenuCommand.trash);
    expect(find.text('Trash'), findsWidgets);
    await send(tester, MenuCommand.showNotes); // pops back home
    expect(find.byKey(const ValueKey('mac-sidebar')), findsOneWidget);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('the toolbar search shows results in the list column', (
    tester,
  ) async {
    await show(tester, macWindowSizes['laptop16']!);
    // View → Search (and ⌘F outside a note) focuses the toolbar field:
    // no search page.
    await send(tester, MenuCommand.search);
    expect(find.byType(SearchScreen), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('mac-toolbar-search')),
      'second',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('mac-list-title'));
    expect(tester.widget<Text>(title).data, 'Search');
    expect(find.byType(SearchResultsView), findsOneWidget);
    // A result opens in the pane beside the results, which stay.
    await tester.tap(
      find.descendant(
        of: find.byType(SearchResultsView),
        matching: find.textContaining('Second note', findRichText: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(find.byType(SearchResultsView), findsOneWidget);
    // Escape clears it and the list comes back.
    await tester.tap(find.byKey(const ValueKey('mac-toolbar-search')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsView), findsNothing);
    expect(tester.widget<Text>(title).data, 'Notes');
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('attachments fill the window from the list menu; Done leaves', (
    tester,
  ) async {
    await show(tester, macWindowSizes['laptop16']!);
    await tester.tap(find.byKey(const ValueKey('mac-list-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Attachments'));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentsBrowserScreen), findsOneWidget);
    expect(find.text('Attachments'), findsOneWidget);
    // In place of list and pane, not a page over them.
    expect(find.byKey(const ValueKey('mac-list')), findsNothing);
    expect(find.byKey(const ValueKey('mac-sidebar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mac-attachments-done')));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentsBrowserScreen), findsNothing);
    expect(find.byKey(const ValueKey('mac-list')), findsOneWidget);
    // View → Attachments too; choosing a sidebar row leaves.
    await send(tester, MenuCommand.showAttachments);
    expect(find.byType(AttachmentsBrowserScreen), findsOneWidget);
    await tester.tap(find.text('All Papers'));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentsBrowserScreen), findsNothing);
    expect(find.text('Your library is empty'), findsOneWidget);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('a page pushed over home gets the slim title bar', (
    tester,
  ) async {
    await show(tester, macWindowSizes['laptop13']!);
    window.toolbarCalls.clear();
    await send(tester, MenuCommand.trash);
    expect(find.byType(TrashScreen), findsOneWidget);
    expect(window.toolbarCalls, [false]);
    // Its app bar sits under the slim title bar, clear of the lights.
    final bar = tester.getRect(
      find.descendant(
        of: find.byType(TrashScreen),
        matching: find.byType(AppBar),
      ),
    );
    expect(bar.top, 0);
    expect(
      tester.getRect(find.byType(BackButton)).top,
      greaterThanOrEqualTo(macTitleBarHeight),
    );
    await send(tester, MenuCommand.back);
    expect(window.toolbarCalls, [false, true]);
    // A dialog over home keeps the toolbar row.
    await send(tester, MenuCommand.keyboardShortcuts);
    expect(window.toolbarCalls, [false, true]);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('with the sidebar hidden the list row clears the lights', (
    tester,
  ) async {
    await show(tester, macWindowSizes['laptop13']!);
    await tester.tap(find.byKey(const ValueKey('mac-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mac-sidebar')), findsNothing);
    final show_ = find.byKey(const ValueKey('mac-show-sidebar'));
    expect(
      tester.getRect(show_).left,
      greaterThanOrEqualTo(macTrafficLightsWidth),
    );
    await tester.tap(show_);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mac-sidebar')), findsOneWidget);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('File → Duplicate Note and Print… act on the open note', (
    tester,
  ) async {
    await show(tester, macWindowSizes['laptop13']!);
    expect(find.text('Today'), findsOneWidget, reason: 'date group header');
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();

    await send(tester, MenuCommand.duplicateNote);
    await tester.runAsync(() async {
      final titles = [for (final n in await db.select(db.notes).get()) n.title];
      expect(titles.where((t) => t == 'First note'), hasLength(2));
    });
    await tester.pumpAndSettle();

    // Database reads need frames, the PDF renderer real time: alternate.
    window.commands.add(MenuCommand.printNote);
    for (var i = 0; i < 60 && window.printed.isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pumpAndSettle();
    expect(window.printed, hasLength(1));
    final (pdf, title) = window.printed.single;
    expect(title, 'First note');
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('dragging the divider resizes and clamps the list', (
    tester,
  ) async {
    await show(tester, macWindowSizes['display27']!);
    final list = find.byKey(const ValueKey('mac-list'));
    expect(tester.getSize(list).width, macListDefaultWidth);
    final divider = find.byType(ColumnDivider);

    await tester.drag(divider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, greaterThan(macListDefaultWidth + 20));

    await tester.drag(divider, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, macListMaxWidth);

    await tester.drag(divider, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, macListMinWidth);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('settings is a dialog on the Mac', (tester) async {
    await show(tester, macWindowSizes['laptop13']!);
    await send(tester, MenuCommand.settings);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    await macScreenshot(tester, 'settings');
    final w = tester
        .getSize(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(ConstrainedBox),
              )
              .first,
        )
        .width;
    expect(w, lessThanOrEqualTo(520));
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('back pops a pushed page, and does nothing at home', (
    tester,
  ) async {
    await show(tester, macWindowSizes['laptop13']!);
    await send(tester, MenuCommand.back);
    expect(find.byKey(const ValueKey('mac-sidebar')), findsOneWidget);
    await send(tester, MenuCommand.trash);
    expect(find.byType(TrashScreen), findsOneWidget);
    await send(tester, MenuCommand.back);
    expect(find.byType(TrashScreen), findsNothing);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('editor commands with no editor focused do nothing', (
    tester,
  ) async {
    // Empty switch cases fall through: Bold et al. once fell into
    // "Close All Locked Notes", so ⌘B in the list locked every note.
    final lock = _CountingLockService(db);
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(
            const NoShareIntentSource(),
          ),
          macWindowProvider.overrideWithValue(window),
          noteLockServiceProvider.overrideWith((ref) => lock),
        ],
        child: const CorplexApp(),
      ),
    );
    await tester.pumpAndSettle();
    for (final c in [
      MenuCommand.bold,
      MenuCommand.heading,
      MenuCommand.insertTable,
      MenuCommand.citePaper,
      MenuCommand.collapseSections,
      MenuCommand.expandSections,
    ]) {
      await send(tester, c);
    }
    expect(lock.locks, 0);
    await send(tester, MenuCommand.lockAllNotes);
    expect(lock.locks, 1);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('move to trash trashes the open note, with Undo', (tester) async {
    await show(tester, macWindowSizes['laptop13']!);
    await send(tester, MenuCommand.moveToTrash); // nothing open: no-op
    expect(find.text('First note'), findsOneWidget);
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    await send(tester, MenuCommand.moveToTrash);
    expect(find.textContaining('moved to trash'), findsOneWidget);
    expect(find.byType(NoteEditorScreen), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('First note'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('keyboard shortcuts opens a dialog; Esc closes it', (
    tester,
  ) async {
    await show(tester, macWindowSizes['laptop13']!);
    await send(tester, MenuCommand.keyboardShortcuts);
    expect(find.byKey(const ValueKey('keyboard-shortcuts')), findsOneWidget);
    expect(find.text('Notes & Formatting'), findsOneWidget);
    await macScreenshot(tester, 'shortcuts');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keyboard-shortcuts')), findsNothing);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('Tab moves focus sidebar, list, detail', (tester) async {
    await show(tester, macWindowSizes['laptop13']!);
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();
    // 0 sidebar, 1 list, 2 detail.
    int region() {
      final box =
          FocusManager.instance.primaryFocus!.context!.findRenderObject()!
              as RenderBox;
      final x = box.localToGlobal(box.size.center(Offset.zero)).dx;
      return x < 233 ? 0 : (x < 580 ? 1 : 2);
    }

    // The editor owns Tab while it has focus (indent), so start from the
    // sidebar's first control and walk forwards.
    FocusManager.instance.primaryFocus?.unfocus();
    Focus.of(tester.element(find.byKey(const ValueKey('mac-new-folder'))))
        .requestFocus();
    await tester.pump();
    final seen = <int>[region()];
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final r = FocusManager.instance.primaryFocus?.context == null
          ? -1
          : region();
      if (seen.isEmpty || seen.last != r) seen.add(r);
    }
    expect(seen, containsAllInOrder([0, 1, 2]));
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('a focused sidebar row shows a ring', (tester) async {
    await show(tester, macWindowSizes['laptop13']!);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await macScreenshot(tester, 'focus-ring');
    // Return activates the focused row.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('a deeper MenuCommandHandler takes a command first', (
    tester,
  ) async {
    var hits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MenuCommandHandler(
          commands: {MenuCommand.find: () => hits++},
          child: const Focus(autofocus: true, child: SizedBox()),
        ),
      ),
    );
    await tester.pump();
    expect(dispatchMenuCommand(MenuCommand.find), isTrue);
    expect(hits, 1);
    expect(dispatchMenuCommand(MenuCommand.back), isFalse);
  }, variant: macOnly);
}

class _CountingLockService extends NoteLockService {
  _CountingLockService(super.db);
  int locks = 0;

  @override
  void lockNow() {
    locks++;
    super.lockNow();
  }
}
