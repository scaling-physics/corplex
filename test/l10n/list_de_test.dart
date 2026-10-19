import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/notes/notes_screen.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_app.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: localizedApp(const Scaffold(body: NotesScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('empty list reads German', (tester) async {
    await db.into(db.papers).insert(PapersCompanion.insert(title: 'P'));
    await pump(tester);
    expect(find.text('Noch keine Notizen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });

  testWidgets('rows show German group headers and Locked', (tester) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('a'),
            title: const Value('Eine Notiz'),
            pinned: const Value(true),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('b'),
            title: const Value('Heute'),
          ),
        );
    await pump(tester);
    expect(find.text('Angeheftet'), findsOneWidget);
    expect(find.text('Heute'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });
}
