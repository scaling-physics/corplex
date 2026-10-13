import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/notes/note_versions.dart';
import 'package:corplex/features/notes/note_versions_screen.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String body(List<String> lines) => jsonEncode([
  {'insert': '${lines.join('\n')}\n'},
]);

void main() {
  late AppDatabase db;
  var flushed = 0;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    flushed = 0;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            title: const Value('Ch 1'),
            content: Value(body(['alpha beta', 'gamma'])),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showNoteVersions(
                  context,
                  noteId: 'n',
                  flush: () async => flushed++,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('empty state, save, compare and restore', (tester) async {
    await open(tester);
    expect(flushed, 1, reason: 'pending typing is saved first');
    expect(find.text('No versions yet'), findsOneWidget);

    await tester.tap(find.text('Save a version now'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Draft 1'), findsOneWidget);
    expect(find.textContaining('3 words'), findsOneWidget);

    await (db.update(db.notes)..where((n) => n.id.equals('n'))).write(
      NotesCompanion(
        content: Value(body(['alpha beta', 'delta epsilon zeta'])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('+2 since'), findsOneWidget);

    await tester.tap(find.text('Draft 1'));
    await tester.pumpAndSettle();
    expect(find.text('gamma'), findsOneWidget);
    expect(find.text('delta epsilon zeta'), findsOneWidget);
    expect(find.byKey(const ValueKey('diff-removed')), findsOneWidget);
    expect(find.byKey(const ValueKey('diff-added')), findsOneWidget);

    await tester.tap(find.text('Restore this version'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals('n'))).getSingle();
    expect(note.content, body(['alpha beta', 'gamma']));
    expect(find.text(beforeRestoringLabel), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('delete offers undo; rename changes the label', (tester) async {
    await saveNoteVersion(db, 'n', label: 'Old');
    await open(tester);

    await tester.tap(find.byTooltip('Version options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Newer');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(find.text('Newer'), findsOneWidget);

    await tester.tap(find.byTooltip('Version options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No versions yet'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Newer'), findsOneWidget);
    await dispose(tester);
  });
}
