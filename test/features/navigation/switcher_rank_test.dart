import 'package:corplex/features/navigation/switcher_rank.dart';
import 'package:corplex/features/notes/note_sections.dart' show NoteHeading;
import 'package:flutter_test/flutter_test.dart';

SwitcherItem note(
  String title, {
  List<String> keywords = const [],
  DateTime? at,
  bool pinned = false,
  String id = '',
}) => SwitcherItem(
  kind: SwitcherKind.note,
  id: id.isEmpty ? title : id,
  title: title,
  keywords: keywords,
  updatedAt: at,
  pinned: pinned,
);

List<String> titles(List<SwitcherItem> l) => [for (final i in l) i.title];

void main() {
  group('matchTier', () {
    test('tiers', () {
      expect(matchTier('sleep', 'sleep'), 0);
      expect(matchTier('sle', 'sleep'), 1);
      expect(matchTier('rep', 'memory replay'), 2);
      expect(matchTier('lee', 'sleep'), 3);
      expect(matchTier('replay sleep', 'sleep and replay'), 4);
      expect(matchTier('slp', 'sleep'), 5);
      expect(matchTier('xyz', 'sleep'), isNull);
      expect(matchTier('', 'sleep'), isNull);
    });
  });

  group('rankSwitcherItems', () {
    test('exact beats prefix beats word-prefix beats inside beats letters', () {
      final r = rankSwitcherItems([
        note('Asleep'),
        note('S l e e p stuff'),
        note('Deep sleep notes'),
        note('Sleepy'),
        note('Sleep'),
      ], 'sleep');
      expect(titles(r), [
        'Sleep',
        'Sleepy',
        'Deep sleep notes',
        'Asleep',
        'S l e e p stuff',
      ]);
    });

    test('subsequence matches come last', () {
      final r = rankSwitcherItems([
        note('Slow weekly plan'),
        note('Sleep'),
      ], 'slp');
      expect(titles(r), ['Sleep', 'Slow weekly plan']);
    });

    test('case and accents are ignored', () {
      final r = rankSwitcherItems([
        note('Müller 2019'),
        note('Café'),
      ], 'MULLER');
      expect(titles(r), ['Müller 2019']);
      expect(titles(rankSwitcherItems([note('Café')], 'cafe')), ['Café']);
    });

    test('a title match beats an alias match of the same quality', () {
      final r = rankSwitcherItems([
        note('Other', keywords: ['hippocampus']),
        note('Hippocampus'),
      ], 'hippocampus');
      expect(titles(r), ['Hippocampus', 'Other']);
    });

    test('aliases, authors and citekeys are found', () {
      final r = rankSwitcherItems([
        note('Replay', keywords: ['Sharp-wave ripples']),
        const SwitcherItem(
          kind: SwitcherKind.paper,
          id: 'p',
          title: 'Attention is all you need',
          keywords: ['Vaswani, Ashish', 'vaswani2017'],
        ),
      ], 'vaswani2017');
      expect(titles(r), ['Attention is all you need']);
      expect(
        titles(
          rankSwitcherItems([
            note('Replay', keywords: ['Sharp-wave']),
          ], 'wave'),
        ),
        ['Replay'],
      );
    });

    test('ties go to pinned, then the most recent, then the title', () {
      final r = rankSwitcherItems([
        note('Alpha b', at: DateTime(2026, 1, 1)),
        note('Alpha a', at: DateTime(2026, 3, 1)),
        note('Alpha c', pinned: true, at: DateTime(2025, 1, 1)),
        note('Alpha d'),
      ], 'alpha');
      expect(titles(r), ['Alpha c', 'Alpha a', 'Alpha b', 'Alpha d']);
    });

    test('a title with no date sorts alphabetically among undated', () {
      final r = rankSwitcherItems([note('Beta two'), note('Beta one')], 'beta');
      expect(titles(r), ['Beta one', 'Beta two']);
    });

    test('empty query keeps order and honours the limit', () {
      final items = [for (var i = 0; i < 50; i++) note('n$i')];
      final r = rankSwitcherItems(items, '  ');
      expect(r, hasLength(40));
      expect(r.first.title, 'n0');
      expect(rankSwitcherItems(items, '', limit: 3), hasLength(3));
    });

    test('caps matches at 40', () {
      final items = [for (var i = 0; i < 100; i++) note('Note $i')];
      expect(rankSwitcherItems(items, 'note'), hasLength(40));
    });

    test('no match gives nothing', () {
      expect(rankSwitcherItems([note('Sleep')], 'qqq'), isEmpty);
    });

    test('multi-word query finds words in any order', () {
      final r = rankSwitcherItems([
        note('Replay during sleep'),
      ], 'sleep replay');
      expect(titles(r), ['Replay during sleep']);
    });

    test('different kinds are ranked together', () {
      final r = rankSwitcherItems([
        note('Thesis plan'),
        const SwitcherItem(
          kind: SwitcherKind.project,
          id: 'x',
          title: 'Thesis',
        ),
      ], 'thesis');
      expect(r.first.kind, SwitcherKind.project);
    });
  });

  group('headings', () {
    const hs = [
      NoteHeading('Introduction', 1, 0),
      NoteHeading('Methods', 2, 40),
      NoteHeading('Results', 2, 90),
      NoteHeading('Method limits', 3, 120),
    ];
    test('empty query lists all in order', () {
      expect(rankHeadings(hs, ''), [0, 1, 2, 3]);
    });
    test('ranks by quality then order', () {
      expect(rankHeadings(hs, 'method'), [1, 3]);
      expect(rankHeadings(hs, 'res'), [2]);
      expect(rankHeadings(hs, 'zzz'), isEmpty);
    });
    test('adjacentHeading', () {
      expect(adjacentHeading(hs, 0, forward: true)?.text, 'Methods');
      expect(adjacentHeading(hs, 45, forward: true)?.text, 'Results');
      expect(adjacentHeading(hs, 200, forward: true), isNull);
      expect(adjacentHeading(hs, 45, forward: false)?.text, 'Methods');
      expect(adjacentHeading(hs, 40, forward: false)?.text, 'Introduction');
      expect(adjacentHeading(hs, 0, forward: false), isNull);
    });
  });

  group('switcherRecents', () {
    final a = note('A', id: 'a'),
        b = note('B', id: 'b'),
        c = note('C', id: 'c');
    final byKey = {'note:a': a, 'note:b': b, 'note:c': c};
    test('newest first, de-duplicated, minus current and deleted', () {
      final r = switcherRecents(
        historyNewestFirst: [
          'note:a',
          'note:gone',
          'note:b',
          'note:a',
          'note:c',
        ],
        byKey: byKey,
        pinned: const [],
        currentKey: 'note:a',
      );
      expect(titles(r.recent), ['B', 'C']);
    });
    test('limit and pinned that are not already recent', () {
      final p = note('P', id: 'p', pinned: true);
      final r = switcherRecents(
        historyNewestFirst: ['note:b', 'note:c'],
        byKey: byKey,
        pinned: [p, b],
        limit: 1,
      );
      expect(titles(r.recent), ['B']);
      expect(titles(r.pinned), ['P']);
    });
  });
}
