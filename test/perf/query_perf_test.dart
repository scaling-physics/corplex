// Timings for the queries behind every list, the search index and the sync
// bookkeeping, on a library of 1,500 papers / 3,000 notes / 20,000
// highlights. Prints `PERF <name> <ms>`; asserts only generous ceilings, so
// it flags a regression (an accidental O(n^2), a lost index) without being
// flaky on a slow machine.
//
//   flutter test test/perf/query_perf_test.dart
//
// Set PERF_SMALL=1 for a quick smoke run on a tenth of the data.
import 'dart:io';
import 'dart:math';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/trash.dart';
import 'package:corplex/features/attachments/attachments_providers.dart';
import 'package:corplex/features/library/all_highlights_screen.dart';
import 'package:corplex/features/library/papers_providers.dart';
import 'package:corplex/features/notes/folders_providers.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/notes_providers.dart';
import 'package:corplex/features/projects/projects_providers.dart';
import 'package:corplex/features/search/note_search_text.dart';
import 'package:corplex/features/search/search_index.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'seed_library.dart';

final _small = Platform.environment['PERF_SMALL'] == '1';

Future<Duration> _time(String name, Future<void> Function() body) async {
  final watch = Stopwatch()..start();
  await body();
  watch.stop();
  // ignore: avoid_print
  print('PERF ${name.padRight(46)} ${_ms(watch.elapsed)} ms');
  return watch.elapsed;
}

String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);

void main() {
  late Directory dir;
  late AppDatabase db;
  late SeededLibrary lib;
  late ProviderContainer container;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('corplex-perf');
    db = AppDatabase.forTesting(
      NativeDatabase(
        File('${dir.path}/perf.sqlite'),
        setup: (d) {
          d.execute('PRAGMA foreign_keys = ON;');
          d.execute('PRAGMA secure_delete = ON;');
        },
      ),
    );
    final size = _small
        ? const LibrarySize(papers: 150, notes: 300, highlights: 2000)
        : const LibrarySize();
    await _time('seed library', () async {
      lib = await seedLibrary(db, size: size);
    });
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDownAll(() async {
    container.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  /// First emission of an autoDispose stream provider, kept alive meanwhile.
  Future<T> first<T>(StreamProvider<T> p) async {
    final sub = container.listen(p, (_, _) {});
    try {
      return await container.read(p.future);
    } finally {
      sub.close();
    }
  }

  test('list providers', () async {
    var notes = <Note>[];
    await _time('notes list: all (pinned first)', () async {
      container.read(notesFilterProvider.notifier).state = const AllNotes();
      notes = await first(visibleNotesProvider);
    });
    expect(notes.length, lib.noteIds.length);
    expect(notes.first.pinned, isTrue);
    await _time('notes list: folder filter', () async {
      container.read(notesFilterProvider.notifier).state = FolderFilter(
        lib.folderIds[3],
      );
      await first(visibleNotesProvider);
    });
    await _time('notes list: tag filter', () async {
      container.read(notesFilterProvider.notifier).state = TagFilter(
        lib.tagIds[3],
      );
      await first(visibleNotesProvider);
    });
    await _time('notes list: project filter', () async {
      container.read(notesFilterProvider.notifier).state = ProjectFilter(
        lib.projectIds[3],
      );
      await first(visibleNotesProvider);
    });
    container.read(notesFilterProvider.notifier).state = const AllNotes();

    await _time('previews of every note (notePlainTextPreview)', () async {
      for (final n in notes) {
        notePlainTextPreview(n.content);
      }
    });
    await _time('previews of 40 notes scrolled back to (cached)', () async {
      for (final n in notes.reversed.take(40)) {
        notePlainTextPreview(n.content);
      }
    });
    await _time('search text of every note (noteSearchText)', () async {
      for (final n in notes) {
        noteSearchText(n.content);
      }
    });

    await _time('library list (papers, newest first)', () async {
      await first(papersListProvider);
    });
    await _time('library filtered by text "neur"', () async {
      container.read(librarySearchProvider.notifier).state = 'neur';
      final sub = container.listen(filteredPapersProvider, (_, _) {});
      await container.read(papersListProvider.future);
      container.read(filteredPapersProvider);
      sub.close();
    });
    await _time('sidebar: folder note counts', () async {
      await first(folderNoteCountsProvider);
    });
    await _time('sidebar: project note counts', () async {
      await first(projectNoteCountsProvider);
    });
    await _time('attachments browser', () async {
      await first(allAttachmentsProvider);
    });
    await _time('all highlights', () async {
      final all = await first(allHighlightsProvider);
      expect(all.length, lib.paperIds.isEmpty ? 0 : greaterThan(0));
    });
  });

  test('search index', () async {
    final index = SearchIndex(db);
    final cold = await _time(
      'search: refresh (cold, builds the index)',
      () async {
        await index.refresh();
      },
    );
    final warm = await _time(
      'search: refresh (warm, nothing changed)',
      () async {
        await index.refresh();
      },
    );
    await _time('search: refresh x5 (warm)', () async {
      for (var i = 0; i < 5; i++) {
        await index.refresh();
      }
    });
    for (final q in [
      'neur',
      'neural cortex',
      'transformer attention',
      'zzzz',
    ]) {
      await _time('search: query "$q" (warm)', () async {
        await index.search(q);
      });
    }
    // One edit: refresh should only re-read that row.
    await db.customUpdate(
      "UPDATE notes SET title = 'Edited title' WHERE id = ?",
      variables: [Variable.withString(lib.noteIds[10])],
      updates: {db.notes},
    );
    await _time('search: refresh after one edited note', () async {
      await index.refresh();
    });
    final edited = await index.search('"Edited title"');
    expect(edited.map((h) => h.id), contains(lib.noteIds[10]));
    expect(warm, lessThan(cold));
    expect(cold.inSeconds, lessThan(120));
  });

  test('sync bookkeeping and trash', () async {
    await _time('sync: pendingChanges() count', () async {
      final row = await db
          .customSelect(
            'SELECT (SELECT COUNT(*) FROM sync_dirty) + '
            '(SELECT COUNT(*) FROM sync_tombstones) AS c',
          )
          .getSingle();
      expect(row.read<int>('c'), greaterThan(0));
    });
    await _time('edit one note (triggers + notify)', () async {
      await (db.update(db.notes)..where((n) => n.id.equals(lib.noteIds[20])))
          .write(const NotesCompanion(title: Value('Another title')));
    });
    // A big note: 400 paragraphs, 40 strokes, a table.
    final big = noteBody(Random(3), const [], big: true);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('big-note'),
            title: const Value('Huge note'),
            content: Value(big),
          ),
        );
    await _time('trash a large note (${big.length ~/ 1024} KB body)', () async {
      await trashNote(db, 'big-note');
    });
    await _time('preview of the large note', () async {
      notePlainTextPreview(big);
    });
  });

  test('per-item queries and deletes', () async {
    await _time('100x highlights of one paper', () async {
      for (var i = 0; i < 100; i++) {
        await (db.select(
          db.highlights,
        )..where((h) => h.paperId.equals(lib.paperIds[i]))).get();
      }
    });
    await _time('100x attachments of one note', () async {
      for (var i = 0; i < 100; i++) {
        await (db.select(
          db.attachments,
        )..where((a) => a.noteId.equals(lib.noteIds[i * 5]))).get();
      }
    });
    await _time('100x notes linked to one paper', () async {
      for (var i = 0; i < 100; i++) {
        await (db.select(
          db.notePaperRefs,
        )..where((r) => r.paperId.equals(lib.paperIds[i]))).get();
      }
    });
    await _time('trash 20 papers (13 highlights each)', () async {
      for (var i = 0; i < 20; i++) {
        await trashPaper(db, lib.paperIds[100 + i]);
      }
    });
    await _time('delete 20 notes (cascades)', () async {
      for (var i = 0; i < 20; i++) {
        await (db.delete(
          db.notes,
        )..where((n) => n.id.equals(lib.noteIds[200 + i * 5]))).go();
      }
    });
  });
}
