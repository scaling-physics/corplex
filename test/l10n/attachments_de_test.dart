import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/attachments/attachments_browser.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/add_attachment_sheet.dart';
import 'package:corplex/features/zotero/zotero_dialog.dart';
import 'package:corplex/features/zotero/zotero_credentials.dart';
import 'package:corplex/features/zotero/zotero_import.dart';
import 'package:corplex/l10n/l10n.dart';

import '../support/fake_audio_engine.dart';
import '../support/l10n_app.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('attachments browser: empty state and filters', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app() => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      ],
      child: localizedApp(const AttachmentsBrowserScreen()),
    );
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Anhänge'), findsOneWidget);
    expect(find.text('Noch keine Anhänge'), findsOneWidget);

    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('p'), title: ''));
    for (final (id, type, url) in [
      ('a1', AttachmentType.podcast, 'https://example.org/a.mp3'),
      ('a2', AttachmentType.link, 'https://example.org/x'),
    ]) {
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: Value(id),
              type: type,
              paperId: const Value('p'),
              url: Value(url),
            ),
          );
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alle'), findsOneWidget);
    expect(find.textContaining('Paper ohne Titel'), findsWidgets);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets('add-attachment sheet in German', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: localizedApp(
          Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showAddAttachmentSheet(context, ref, noteId: 'n'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Audio aufnehmen'), findsOneWidget);
    expect(find.text('Podcast-Link'), findsOneWidget);
    expect(find.text('Bild'), findsOneWidget);
    expect(find.text('Datei'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await dispose(tester);
  });

  testWidgets('Zotero dialog asks for the key in German', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: ZoteroImportDialog(db: db, store: _NoCredentials()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Mit Zotero verbinden'), findsOneWidget);
    expect(find.text('Nutzer-ID'), findsOneWidget);
    expect(find.text('API-Schlüssel'), findsOneWidget);
    expect(find.text('Verbinden'), findsOneWidget);
    await dispose(tester);
  });

  test('Zotero summary reads in German', () {
    final de = lookupAppLocalizations(const Locale('de'));
    final s = ZoteroImportSummary()
      ..papers = 2
      ..pdfs = 1
      ..highlights = 3
      ..projects.add('Thesis');
    expect(
      s.messageFor(de),
      '2 Paper, 1 PDF und 3 Markierungen in 1 Projekt importiert.',
    );
    expect(s.message, startsWith('Imported 2 papers, 1 PDF, 3 highlights'));
  });
}

class _NoCredentials implements ZoteroCredentialStore {
  @override
  Future<ZoteroCredentials?> read() async => null;
  @override
  Future<void> save(ZoteroCredentials c) async {}
  @override
  Future<void> forget() async {}
}
