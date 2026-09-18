import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/papers_providers.dart';
import 'package:corplex/features/notes/note_papers_providers.dart';

/// Waits for [provider] to emit a value satisfying [until]. A StreamProvider's
/// `.future` only reliably reflects the state as of when it's first read, so
/// polling it again after a later write can race the write's notification —
/// this instead listens for the specific change the test cares about.
Future<T> waitFor<T>(
  ProviderContainer container,
  StreamProvider<T> provider,
  bool Function(T) until,
) {
  final completer = Completer<T>();
  // fireImmediately establishes the listen hold and checks the current
  // value in one step — reading separately first leaves a gap where
  // autoDispose can tear the provider down before listen() attaches.
  late final ProviderSubscription<AsyncValue<T>> sub;
  sub = container.listen(provider, (previous, next) {
    final value = next.value;
    if (value != null && until(value) && !completer.isCompleted) {
      completer.complete(value);
      sub.close();
    }
  }, fireImmediately: true);
  return completer.future;
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int noteId;
  late int paperId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    noteId = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(title: const Value('My note')));
    paperId = await db
        .into(db.papers)
        .insert(PapersCompanion.insert(title: 'A paper'));

    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  test('linking a paper to a note is visible from both sides', () async {
    expect(
      await waitFor(container, linkedPapersForNoteProvider(noteId), (_) => true),
      isEmpty,
    );

    await linkPaperToNote(db, noteId: noteId, paperId: paperId);

    final linkedPapers = await waitFor(
      container,
      linkedPapersForNoteProvider(noteId),
      (papers) => papers.isNotEmpty,
    );
    expect(linkedPapers.map((p) => p.id), [paperId]);

    final referencingNotes = await waitFor(
      container,
      notesForPaperProvider(paperId),
      (notes) => notes.isNotEmpty,
    );
    expect(referencingNotes.map((n) => n.id), [noteId]);
  });

  test('linking twice does not create a duplicate (insertOrIgnore)', () async {
    await linkPaperToNote(db, noteId: noteId, paperId: paperId);
    await linkPaperToNote(db, noteId: noteId, paperId: paperId);

    final refs = await db.select(db.notePaperRefs).get();
    expect(refs, hasLength(1));
  });

  test('unlinking removes the reference from both sides', () async {
    await linkPaperToNote(db, noteId: noteId, paperId: paperId);
    await waitFor(
      container,
      linkedPapersForNoteProvider(noteId),
      (papers) => papers.isNotEmpty,
    );

    await unlinkPaperFromNote(db, noteId: noteId, paperId: paperId);

    final linkedPapers = await waitFor(
      container,
      linkedPapersForNoteProvider(noteId),
      (papers) => papers.isEmpty,
    );
    expect(linkedPapers, isEmpty);

    final referencingNotes = await waitFor(
      container,
      notesForPaperProvider(paperId),
      (notes) => notes.isEmpty,
    );
    expect(referencingNotes, isEmpty);
  });
}
