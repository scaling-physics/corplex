import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/lock/note_crypto.dart' show lockedPrefix;
import 'package:corplex/features/navigation/nav_target.dart';
import 'package:corplex/features/spotlight/spotlight_channel.dart';
import 'package:corplex/features/spotlight/spotlight_indexer.dart';
import 'package:corplex/features/spotlight/spotlight_links.dart';

class _FakeSpotlight implements SpotlightChannel {
  final calls = <String>[];
  final batches = <List<SpotlightItem>>[];
  final removed = <String>[];

  @override
  bool get available => true;
  @override
  Future<void> index(List<SpotlightItem> items) async {
    calls.add('index');
    batches.add(items);
  }

  @override
  Future<void> remove(List<String> ids) async {
    calls.add('remove');
    removed.addAll(ids);
  }

  @override
  Future<void> clear() async => calls.add('clear');
  @override
  Stream<String> get opens => const Stream.empty();

  Iterable<SpotlightItem> get indexed => batches.expand((b) => b);
}

void main() {
  late AppDatabase db;
  late _FakeSpotlight channel;
  late MemorySpotlightStamps stamps;
  late SpotlightIndexer indexer;

  Future<void> note(String id, String title, String content) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(title),
          content: Value(content),
          updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(1000000)),
        ),
      );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    channel = _FakeSpotlight();
    stamps = MemorySpotlightStamps();
    indexer = SpotlightIndexer(db, channel, stamps, batchSize: 2);
    await note('n1', 'Mice', 'plain words about mice');
    await note('n2', 'Secret', '${lockedPrefix}k:abcdef');
    await note('n3', 'Third', 'three');
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani, Ashish; Shazeer, Noam'),
            year: const Value(2017),
            venue: const Value('NeurIPS'),
            abstract: const Value('We propose the Transformer.'),
            citekey: const Value('vaswani2017'),
          ),
        );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(id: const Value('pr1'), name: 'Thesis'),
        );
  });
  tearDown(() => db.close());

  test('first pass clears, then indexes everything in batches', () async {
    await indexer.sync();
    expect(channel.calls.first, 'clear');
    expect(channel.batches.every((b) => b.length <= 2), isTrue);
    expect(channel.indexed.map((i) => i.id).toSet(), {
      'note:n1',
      'note:n2',
      'note:n3',
      'paper:p1',
      'project:pr1',
    });
    final paper = channel.indexed.firstWhere((i) => i.id == 'paper:p1');
    expect(paper.keywords, contains('vaswani2017'));
    expect(paper.text, contains('Transformer'));
    expect(paper.subtitle, contains('NeurIPS'));
  });

  test('a locked note goes in by title only', () async {
    await indexer.sync();
    final locked = channel.indexed.firstWhere((i) => i.id == 'note:n2');
    expect(locked.title, 'Secret');
    expect(locked.text, isEmpty);
    expect(locked.subtitle, isEmpty);
    final plain = channel.indexed.firstWhere((i) => i.id == 'note:n1');
    expect(plain.text, contains('mice'));
  });

  test('a second pass with no changes sends nothing', () async {
    await indexer.sync();
    channel.calls.clear();
    await indexer.sync();
    expect(channel.calls, isEmpty);
  });

  test('only changed rows are re-indexed and deleted ones removed', () async {
    await indexer.sync();
    channel.calls.clear();
    channel.batches.clear();
    await (db.update(db.notes)..where((n) => n.id.equals('n3'))).write(
      NotesCompanion(
        title: const Value('Third, edited'),
        updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(9000000)),
      ),
    );
    await (db.delete(db.projects)..where((p) => p.id.equals('pr1'))).go();
    await indexer.sync();
    expect(channel.indexed.map((i) => i.id), ['note:n3']);
    expect(channel.removed, ['project:pr1']);
  });

  test('locking a note re-indexes it without its text', () async {
    await indexer.sync();
    channel.batches.clear();
    await (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
      NotesCompanion(content: Value('${lockedPrefix}k:zzz')),
    );
    await indexer.sync();
    final again = channel.indexed.firstWhere((i) => i.id == 'note:n1');
    expect(again.text, isEmpty);
  });

  test('missing stamps rebuild from scratch', () async {
    await indexer.sync();
    stamps.stamps = null;
    channel.calls.clear();
    channel.batches.clear();
    await indexer.sync();
    expect(channel.calls.first, 'clear');
    expect(channel.indexed, hasLength(5));
  });

  test('clear empties Spotlight and the stamps', () async {
    await indexer.sync();
    await indexer.clear();
    expect(channel.calls.last, 'clear');
    expect(stamps.stamps, isEmpty);
  });

  test('result ids map to links and back to places', () {
    expect(
      spotlightLinkFor(const NoteTarget('abc').key).toString(),
      'corplex://note/abc',
    );
    expect(
      navTargetForLink(spotlightLinkFor('paper:p1')!),
      const PaperTarget('p1'),
    );
    expect(
      navTargetForLink(spotlightLinkFor('project:x')!),
      const ProjectTarget('x'),
    );
    expect(spotlightLinkFor('bogus:1'), isNull);
    expect(spotlightLinkFor('note:'), isNull);
    expect(navTargetForLink(Uri.parse('https://example.com/a')), isNull);
  });
}
