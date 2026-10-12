import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/study_details.dart';
import 'package:corplex/features/library/study_details_section.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
  });

  Future<void> insert(String id, {PapersCompanion? extra}) => db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(id: Value(id), title: 'Paper $id').copyWith(
          species: extra?.species,
          sampleSize: extra?.sampleSize,
          techniques: extra?.techniques,
        ),
      );

  Future<Paper> paper(String id) =>
      (db.select(db.papers)..where((p) => p.id.equals(id))).getSingle();

  // The section is fed by the same stream the paper screen uses.
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer(
                builder: (context, ref, _) {
                  final p = ref.watch(_paperProvider).value;
                  return p == null
                      ? const SizedBox()
                      : StudyDetailsSection(paper: p);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  }

  testWidgets('hidden until used, then asks for nothing more', (tester) async {
    await insert('p1');
    await show(tester);
    expect(find.text('Add study details'), findsOneWidget);
    expect(find.text('Study details'), findsNothing);
    await tester.tap(find.text('Add study details'));
    await settle(tester);
    expect(find.text('Study details'), findsOneWidget);
    expect(find.text('Species / model'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('shows at once when the paper has details', (tester) async {
    await insert('p1', extra: PapersCompanion(species: const Value('mouse')));
    await show(tester);
    expect(find.text('Add study details'), findsNothing);
    expect(find.text('Study details'), findsOneWidget);
    expect(find.byKey(const ValueKey('chip-species-mouse')), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('chips: enter and comma add, x removes, saved', (tester) async {
    await insert('p1', extra: PapersCompanion(species: const Value('mouse')));
    await show(tester);
    final input = find.byKey(const ValueKey('input-species'));
    await tester.enterText(input, 'rat');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect((await paper('p1')).species, 'mouse; rat');

    await tester.enterText(input, 'zebrafish,');
    await settle(tester);
    expect((await paper('p1')).species, 'mouse; rat; zebrafish');

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chip-species-mouse')),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await settle(tester);
    expect((await paper('p1')).species, 'rat; zebrafish');
    await dispose(tester);
  });

  testWidgets('suggests library values first, filtered as you type', (
    tester,
  ) async {
    await insert('p1', extra: PapersCompanion(species: const Value('mouse')));
    await insert('p2', extra: PapersCompanion(species: const Value('axolotl')));
    await show(tester);
    final input = find.byKey(const ValueKey('input-species'));
    await tester.tap(input);
    await settle(tester);
    // axolotl is in the library (not the built-in list) and is offered;
    // "mouse" is already chosen here.
    expect(
      find.byKey(const ValueKey('suggest-species-axolotl')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('suggest-species-mouse')), findsNothing);
    expect(find.byKey(const ValueKey('suggest-species-rat')), findsOneWidget);

    await tester.enterText(input, 'axo');
    await settle(tester);
    expect(
      find.byKey(const ValueKey('suggest-species-axolotl')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('suggest-species-rat')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('suggest-species-axolotl')));
    await settle(tester);
    expect((await paper('p1')).species, 'mouse; axolotl');
    await dispose(tester);
  });

  testWidgets('sample size rejects non-numbers and saves numbers', (
    tester,
  ) async {
    await insert('p1', extra: PapersCompanion(species: const Value('mouse')));
    await show(tester);
    final input = find.byKey(const ValueKey('input-sample_size'));
    await tester.enterText(input, 'abc');
    await settle(tester);
    expect(tester.widget<TextField>(input).controller!.text, '');
    expect((await paper('p1')).sampleSize, isNull);
    await tester.enterText(input, '1a2');
    await settle(tester);
    expect(tester.widget<TextField>(input).controller!.text, '12');
    expect((await paper('p1')).sampleSize, 12);
    await dispose(tester);
  });

  testWidgets('outside changes land in untouched fields only', (tester) async {
    await insert(
      'p1',
      extra: PapersCompanion(
        species: const Value('mouse'),
        sampleSize: const Value(5),
      ),
    );
    await show(tester);
    final n = find.byKey(const ValueKey('input-sample_size'));
    expect(tester.widget<TextField>(n).controller!.text, '5');

    // A sync changes species (untouched) and n (being typed over).
    await tester.enterText(n, '50');
    await setStudyValue(db, 'p1', StudyField.species, 'mouse; rat');
    await db.customStatement('UPDATE papers SET sample_size = 7 WHERE id = ?', [
      'p1',
    ]);
    await settle(tester);
    expect(find.byKey(const ValueKey('chip-species-rat')), findsOneWidget);
    expect(tester.widget<TextField>(n).controller!.text, '50');
    await dispose(tester);
  });
}

final _paperProvider = StreamProvider.autoDispose<Paper?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.papers,
  )..where((p) => p.id.equals('p1'))).watchSingleOrNull();
});
