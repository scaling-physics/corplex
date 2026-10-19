import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/trash.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/auth/auth_service.dart';
import 'package:corplex/features/auth/sign_in_screen.dart';
import 'package:corplex/features/auth/sign_up_screen.dart';
import 'package:corplex/features/home/keyboard_shortcuts.dart';
import 'package:corplex/features/lock/lock_screen.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:corplex/features/lock/notes_password_dialogs.dart';
import 'package:corplex/features/search/search_screen.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:corplex/features/sync/sync_messages.dart';
import 'package:corplex/features/sync/sync_service.dart';
import 'package:corplex/features/trash/trash_screen.dart';
import 'package:corplex/l10n/l10n.dart';

import '../support/fake_audio_engine.dart';
import '../support/l10n_app.dart';
import '../support/mac_screenshot.dart';

void main() {
  late AppDatabase db;

  setUpAll(loadMacFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Widget scoped(Widget child) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      shareIntentSourceProvider.overrideWithValue(const NoShareIntentSource()),
    ],
    child: child,
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the home shell and account sheet read German on a phone', (
    tester,
  ) async {
    phone(tester);
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(scoped(const CorplexApp()));
    await tester.pumpAndSettle();

    expect(find.text('Notizen'), findsWidgets);
    expect(find.text('Bibliothek'), findsWidgets);
    expect(find.text('Willkommen bei Corplex'), findsOneWidget);
    expect(find.text('Neue Notiz'), findsWidgets);

    await tester.tap(find.byTooltip('Anmelden'));
    await tester.pumpAndSettle();
    expect(find.text('Papierkorb'), findsOneWidget);
    expect(find.text('In Datei sichern'), findsOneWidget);
    expect(find.text('Aus Backup wiederherstellen'), findsOneWidget);
    expect(find.text('Erscheinungsbild'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await teardownTree(tester);
  });

  testWidgets('the Mac sidebar and toolbar fit the minimum window in German', (
    tester,
  ) async {
    await loadMacFonts();
    useMacWindow(tester, macWindowSizes['minimum']!);
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Eine Notiz'),
          ),
        );
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

    expect(find.text('Alle Notizen'), findsOneWidget);
    expect(find.text('Alle Paper'), findsOneWidget);
    expect(find.text('Papierkorb'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.byTooltip('Neue Notiz (⌘N)'), findsOneWidget);
    expect(find.text('1 Notiz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await teardownTree(tester);
  }, variant: macOnly);

  testWidgets('keyboard shortcuts, search and trash read German', (
    tester,
  ) async {
    phone(tester);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Weg damit'),
          ),
        );
    await trashNote(db, 'n1');
    await tester.pumpWidget(
      scoped(
        localizedApp(
          Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => showKeyboardShortcuts(context),
                    child: const Text('keys'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TrashScreen(),
                      ),
                    ),
                    child: const Text('trash'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SearchScreen(),
                      ),
                    ),
                    child: const Text('search'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('keys'));
    await tester.pumpAndSettle();
    expect(find.text('Tastaturkurzbefehle'), findsWidgets);
    expect(find.text('Schnellnotiz von überall'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('trash'));
    await tester.pumpAndSettle();
    expect(find.text('Papierkorb'), findsOneWidget);
    expect(find.text('Weg damit'), findsOneWidget);
    expect(find.textContaining('Notiz · noch'), findsOneWidget);
    expect(find.text('Wiederherstellen'), findsOneWidget);
    expect(find.text('Leeren'), findsOneWidget);
    expect(find.textContaining('30 Tage'), findsWidgets);
    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(TrashScreen));
    expect(context.l10n.trashDaysLeft(1), 'noch 1 Tag');
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();
    expect(find.text('Alles durchsuchen'), findsOneWidget);
    expect(
      find.text('Notizen, Paper und Markierungen durchsuchen'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Keine Treffer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await teardownTree(tester);
  });

  testWidgets('sign in and sign up read German and show German errors', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(scoped(localizedApp(const SignInScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(find.text('Passwort'), findsOneWidget);
    expect(find.text('Noch kein Konto? Registrieren'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'keine-mail');
    await tester.enterText(find.byType(TextField).last, 'geheim123');
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();
    expect(find.text('Gültige E-Mail-Adresse eingeben.'), findsOneWidget);

    await tester.pumpWidget(scoped(localizedApp(const SignUpScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Konto erstellen'), findsWidgets);
    expect(find.text('Mindestens 6 Zeichen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await teardownTree(tester);
  });

  testWidgets('lock screen and password dialog read German and stay clear', (
    tester,
  ) async {
    phone(tester);
    final service = NoteLockService(
      db,
      crypto: NoteCrypto(iterations: 1000),
      inlineKdf: true,
    );
    await tester.runAsync(
      () => service.setPassword('hunter22', hint: 'wie immer'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          noteLockServiceProvider.overrideWith((ref) => service),
        ],
        child: localizedApp(const NoteLockScreen(title: '')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Diese Notiz ist gesperrt'), findsOneWidget);
    expect(find.text('Ohne Titel'), findsOneWidget);
    expect(find.text('Hinweis zeigen'), findsOneWidget);
    await tester.tap(find.text('Hinweis zeigen'));
    await tester.pump();
    expect(find.text('Hinweis: wie immer'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'falsch');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Falsches Passwort'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          noteLockServiceProvider.overrideWith((ref) => service),
        ],
        child: localizedApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showSetNotesPasswordDialog(
                context,
                NoteLockService(db, inlineKdf: true),
              ),
              child: const Text('set'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('set'));
    await tester.pumpAndSettle();
    expect(find.text('Notizen-Passwort festlegen'), findsOneWidget);
    expect(find.textContaining('weder von dir noch von uns'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Passwort'), 'abc');
    await tester.enterText(find.widgetWithText(TextField, 'Bestätigen'), 'abc');
    await tester.tap(find.text('Passwort festlegen'));
    await tester.pumpAndSettle();
    expect(find.text('Mindestens 6 Zeichen verwenden.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await teardownTree(tester);
  });

  test('sync and auth errors are translated, other text is left alone', () {
    final de = lookupAppLocalizations(const Locale('de'));
    expect(
      localizedSyncError(de, syncGenericErrorMessage),
      'Synchronisierung nicht möglich. Deine Notizen sind sicher auf diesem Gerät.',
    );
    expect(localizedSyncError(de, 'Server said no'), 'Server said no');
    expect(localizedSyncError(de, null), 'Synchronisierung fehlgeschlagen');
    expect(
      authErrorText(
        de,
        const AuthException(
          'x',
          code: AuthErrorCode.unknown,
          detail: 'StateError',
        ),
      ),
      'Etwas ist schiefgelaufen (StateError). Bitte erneut versuchen.',
    );
    expect(
      authErrorText(de, const AuthException('Invalid login')),
      'Invalid login',
    );
  });
}
