import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/library/library_screen.dart';
import 'package:corplex/features/library/retraction.dart';
import 'package:corplex/features/library/study_details.dart';
import 'package:corplex/l10n/l10n.dart';

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

  Future<void> pumpLibrary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: localizedApp(const Scaffold(body: LibraryScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('empty library, search and menu in German', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('Paper suchen'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Alle Markierungen'), findsOneWidget);
    expect(find.text('Per DOI oder arXiv-ID hinzufügen'), findsOneWidget);
    expect(find.text('Literaturangaben importieren'), findsOneWidget);
    expect(find.text('Aus Zotero importieren …'), findsOneWidget);
    expect(find.text('Als BibTeX exportieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await disposeTree(tester);
  });

  testWidgets('status chips and study chip fit on a phone', (tester) async {
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('a'),
            title: 'Place cells',
            readingStatus: const Value(ReadingStatus.done),
            species: const Value('rat'),
          ),
        );
    await pumpLibrary(tester);
    expect(find.text('Alle'), findsOneWidget);
    expect(find.text('Zu lesen'), findsOneWidget);
    expect(find.text('Am Lesen', skipOffstage: false), findsWidgets);
    expect(find.text('Gelesen', skipOffstage: false), findsWidgets);
    expect(find.text('Studie', skipOffstage: false), findsWidgets);
    expect(find.text('Place cells'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  test('notice text and study labels follow the language', () {
    final de = lookupAppLocalizations(const Locale('de'));
    final notice = UpdateNotice(
      kind: NoticeKind.retraction,
      noticeDoi: '10.1/x',
      date: DateTime.utc(2024, 3, 12),
    );
    expect(
      notice.messageFor(de, 'de'),
      'Zurückgezogen am 12. März 2024 – siehe Hinweis',
    );
    expect(notice.message, 'Retracted on 12 March 2024 — see the notice');
    expect(StudyField.brainRegions.labelFor(de), 'Hirnregionen');
  });
}
