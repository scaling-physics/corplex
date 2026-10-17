import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:corplex/features/lock/notes_password_settings.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/notes/note_lock_actions.dart';
import 'package:corplex/features/notes/notes_screen.dart';
import 'package:corplex/theme/app_theme.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

String _body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

const _secret = 'zebrafish protocol';

void main() {
  late AppDatabase db;
  late NoteLockService service;

  setUpAll(loadMacFonts);

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    service = NoteLockService(
      db,
      crypto: NoteCrypto(iterations: 1000),
      inlineKdf: true,
    );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Grant draft'),
            content: Value(_body(_secret)),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      noteLockServiceProvider.overrideWith((ref) => service),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const NoteEditorScreen(noteId: 'n1')));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<Note> stored() =>
      (db.select(db.notes)..where((n) => n.id.equals('n1'))).getSingle();

  /// A note already locked under "hunter22" (the notes then lock again).
  Future<void> lockedNote(WidgetTester tester) async {
    await tester.runAsync(() async {
      await service.setPassword('hunter22', hint: 'the usual');
      await service.lockNote('n1');
      service.lockNow();
    });
  }

  QuillController controller(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  testWidgets('Lock note from the menu sets a password, then encrypts', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock note'));
    await tester.pumpAndSettle();

    expect(find.text('Set a notes password'), findsOneWidget);
    expect(find.textContaining('can\'t be recovered'), findsOneWidget);
    // Too short is refused.
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'abc');
    await tester.enterText(find.widgetWithText(TextField, 'Confirm'), 'abc');
    await tester.tap(find.text('Set password'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 6'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'hunter22',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm'),
      'hunter22',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Set password'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    final note = await stored();
    expect(isLockedContent(note.content), isTrue);
    expect(note.content, isNot(contains('zebrafish')));
    // Stays open, unlocked, showing the text, with the header lock.
    expect(controller(tester).document.toPlainText(), contains(_secret));
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
    await close(tester);
  });

  testWidgets('a locked note opens on the lock screen; wrong, then right', (
    tester,
  ) async {
    await lockedNote(tester);
    await open(tester);
    expect(find.text('This note is locked'), findsOneWidget);
    expect(find.text('Grant draft'), findsOneWidget);
    await macScreenshot(tester, 'lock_phone');
    expect(find.byType(QuillEditor), findsNothing);
    expect(find.textContaining('zebrafish'), findsNothing);

    await tester.tap(find.text('Show hint'));
    await tester.pump();
    expect(find.text('Hint: the usual'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);
    expect(find.byType(QuillEditor), findsNothing);

    await tester.enterText(find.byType(TextField), 'hunter22');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(controller(tester).document.toPlainText(), contains(_secret));
    await close(tester);
  });

  testWidgets('editing a locked note only ever stores an envelope', (
    tester,
  ) async {
    await lockedNote(tester);
    await tester.runAsync(() => service.unlock('hunter22'));
    await open(tester);

    controller(tester)
        .replaceText(0, 0, 'quokka ', const TextSelection.collapsed(offset: 7));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final note = await stored();
    expect(isLockedContent(note.content), isTrue);
    expect(note.content, isNot(contains('quokka')));
    expect(note.content, isNot(contains('zebrafish')));
    final plain = await service.decryptBody('n1', note.content);
    expect(plain, contains('quokka zebrafish'));
    // Our own save echoing back is not an outside change.
    expect(controller(tester).document.toPlainText(), startsWith('quokka '));
    await close(tester);
  });

  testWidgets('locking while text is unsaved keeps it for the next unlock', (
    tester,
  ) async {
    await lockedNote(tester);
    await tester.runAsync(() => service.unlock('hunter22'));
    await open(tester);

    controller(
      tester,
    ).replaceText(0, 0, 'axolotl ', const TextSelection.collapsed(offset: 8));
    // Typed, not saved yet; the notes lock now.
    service.lockNow();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('This note is locked'), findsOneWidget);
    expect(find.textContaining('axolotl'), findsNothing);
    expect((await stored()).content, isNot(contains('axolotl')));

    await tester.runAsync(() => service.unlock('hunter22'));
    await tester.pumpAndSettle();
    expect(controller(tester).document.toPlainText(), startsWith('axolotl '));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    final plain = await service.decryptBody('n1', (await stored()).content);
    expect(plain, contains('axolotl zebrafish'));
    await close(tester);
  });

  Future<void> typeThenLock(
    WidgetTester tester,
    Future<void> Function(WidgetRef ref, BuildContext context) lock,
  ) async {
    await tester.runAsync(() => service.setPassword('hunter22'));
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      app(
        Column(
          children: [
            Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
            const Expanded(child: NoteEditorScreen(noteId: 'n1')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller(tester)
        .replaceText(0, 0, 'okapi ', const TextSelection.collapsed(offset: 6));
    // Typed; the autosave hasn't fired.
    final locking = lock(capturedRef, capturedContext);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    await locking;
    final note = await stored();
    expect(isLockedContent(note.content), isTrue);
    expect(note.content, isNot(contains('okapi')));
    final plain = await service.decryptBody('n1', note.content);
    expect(plain, contains('okapi zebrafish'));
    await close(tester);
  }

  testWidgets('locking from the list flushes the open editor first', (
    tester,
  ) async {
    await typeThenLock(tester, (ref, context) async {
      final note = await stored();
      await ref.read(openNoteFlushProvider)[note.id]!.call();
      await lockNoteFromList(context, ref, await stored());
    });
  });

  testWidgets('a plain save never overwrites a lock made behind the editor', (
    tester,
  ) async {
    await typeThenLock(tester, (ref, context) => service.lockNote('n1'));
  });

  testWidgets('Remove lock restores plain content', (tester) async {
    await lockedNote(tester);
    await tester.runAsync(() => service.unlock('hunter22'));
    await open(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove lock'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    final note = await stored();
    expect(isLockedContent(note.content), isFalse);
    expect(note.content, contains(_secret));
    await close(tester);
  });

  testWidgets('the list shows the title, a lock and "Locked", no preview', (
    tester,
  ) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n2'),
            title: const Value('Reading list'),
            content: Value(_body('plain visible preview')),
          ),
        );
    await lockedNote(tester);
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const Scaffold(body: NotesScreen())));
    await tester.pumpAndSettle();

    expect(find.textContaining('Grant draft'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.textContaining('zebrafish'), findsNothing);
    expect(find.textContaining('corplex-locked'), findsNothing);
    expect(find.textContaining('plain visible preview'), findsOneWidget);
    await macScreenshot(tester, 'list_phone');
    await close(tester);
  });

  testWidgets('settings: change the password', (tester) async {
    await tester.runAsync(() => service.setPassword('hunter22'));
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: SingleChildScrollView(child: NotesPasswordSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Current password'),
      'hunter22',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'correct horse',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm'),
      'correct horse',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Change password').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      service.lockNow();
      expect(await service.unlock('hunter22'), isFalse);
      expect(await service.unlock('correct horse'), isTrue);
    });
    await close(tester);
  });

  testWidgets('settings show nothing without a password', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: NotesPasswordSettings())));
    await tester.pumpAndSettle();
    expect(find.text('Notes password'), findsNothing);
    await close(tester);
  });

  testWidgets('the Mac list shows a locked note the same way', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await lockedNote(tester);
    await tester.pumpWidget(app(const Scaffold(body: NotesScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Locked'), findsOneWidget);
    expect(find.textContaining('zebrafish'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await macScreenshot(tester, 'list_mac');
    await close(tester);
  }, variant: macOnly);

  testWidgets('lock screen on a Mac', (tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await lockedNote(tester);
    await tester.pumpWidget(
      app(const NoteEditorScreen(noteId: 'n1', embedded: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('This note is locked'), findsOneWidget);
    await macScreenshot(tester, 'lock_mac');
    await close(tester);
  }, variant: macOnly);
}
