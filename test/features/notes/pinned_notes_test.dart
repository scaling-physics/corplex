import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/notes/notes_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    final now = DateTime.now();
    for (final (id, age) in [('old', 3), ('mid', 2), ('new', 1)]) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value(id),
              updatedAt: Value(now.subtract(Duration(days: age))),
            ),
          );
    }
  });
  tearDown(() => db.close());

  test('a pinned note sorts first; unpinning restores recency order', () async {
    await setNotePinned(db, 'old', true);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.listen(notesListProvider, (_, _) {});
    final notes = await container.read(notesListProvider.future);
    expect(notes.first.id, 'old');
    expect(notes.first.pinned, isTrue);
  });

  test('pinning is a synced edit', () async {
    await db.customStatement('DELETE FROM sync_dirty');
    await setNotePinned(db, 'mid', true);
    final dirty = await db
        .customSelect(
          "SELECT row_key FROM sync_dirty WHERE table_name = 'notes'",
        )
        .get();
    expect(
      dirty.map((r) => r.read<String>('row_key')),
      contains(contains('mid')),
    );
  });
}
