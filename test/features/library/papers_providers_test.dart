import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/papers_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  test('search filters papers by title or authors, case-insensitively', () async {
    // Insert before subscribing: a stream query reflects the DB state at
    // the moment it's created, so this avoids racing the provider's first
    // emission against writes that happen after it's already listening.
    await db.into(db.papers).insert(
          PapersCompanion.insert(
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani et al.'),
          ),
        );
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(title: 'Deep Residual Learning'));

    // Pin the autoDispose providers alive for the duration of the test;
    // otherwise container.read releases them between calls and they get
    // torn down mid-stream.
    container.listen(papersListProvider, (_, _) {});
    container.listen(filteredPapersProvider, (_, _) {});

    final allPapers = await container.read(papersListProvider.future);
    expect(allPapers, hasLength(2));

    container.read(librarySearchProvider.notifier).state = 'vaswani';
    final byAuthor = container.read(filteredPapersProvider).requireValue;
    expect(byAuthor.map((p) => p.title), ['Attention Is All You Need']);

    container.read(librarySearchProvider.notifier).state = 'residual';
    final byTitle = container.read(filteredPapersProvider).requireValue;
    expect(byTitle.map((p) => p.title), ['Deep Residual Learning']);

    container.read(librarySearchProvider.notifier).state = '';
    final all = container.read(filteredPapersProvider).requireValue;
    expect(all, hasLength(2));
  });
}
