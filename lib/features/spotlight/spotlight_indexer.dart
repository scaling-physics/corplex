import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../library/authors.dart';
import '../lock/note_crypto.dart' show lockedPrefix;
import '../notes/note_aliases.dart' show parseAliases;
import '../search/note_search_text.dart';
import 'spotlight_channel.dart';

/// What was handed to Spotlight and when: item id → stamp. Per device (the
/// index is), kept outside the database so no schema changes. Null from
/// [load] means "unknown": the index is rebuilt.
abstract class SpotlightStamps {
  Future<Map<String, int>?> load();
  Future<void> save(Map<String, int> stamps);
}

class MemorySpotlightStamps implements SpotlightStamps {
  Map<String, int>? stamps;

  @override
  Future<Map<String, int>?> load() async =>
      stamps == null ? null : Map.of(stamps!);
  @override
  Future<void> save(Map<String, int> stamps) async =>
      this.stamps = Map.of(stamps);
}

/// Stamps in shared_preferences as JSON. A different [version] (the item
/// format changed) counts as missing.
class PrefsSpotlightStamps implements SpotlightStamps {
  const PrefsSpotlightStamps();

  static const key = 'spotlight.stamps';
  static const version = 1;

  @override
  Future<Map<String, int>?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['v'] != version) return null;
      return {
        for (final e in (json['s'] as Map<String, dynamic>).entries)
          e.key: e.value as int,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, int> stamps) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode({'v': version, 's': stamps}),
      );
    } catch (_) {}
  }

  static Future<void> forget() async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (_) {}
  }
}

/// Keeps Spotlight in step with the library: notes (title, aliases, a
/// snippet — a locked note by title only), papers (title, authors, venue,
/// abstract, citekey) and projects. Like `SearchIndex` it compares each
/// row's `updated_at` stamp (a locked note's stamp carries a low bit, so
/// locking re-indexes it and the old text leaves Spotlight), sends only
/// what changed in batches, and removes what is gone. Missing or outdated
/// stamps rebuild everything.
class SpotlightIndexer {
  SpotlightIndexer(
    this._db,
    this._channel,
    this._stamps, {
    this.batchSize = 100,
    this.untitled = 'Untitled',
  });

  final AppDatabase _db;
  final SpotlightChannel _channel;
  final SpotlightStamps _stamps;
  final int batchSize;

  /// Title of a note that has none.
  final String untitled;

  Future<void> _tail = Future.value();

  /// Brings the index up to date. Calls queue, so overlapping ones can't
  /// interleave batches.
  Future<void> sync() {
    final run = _tail.then((_) => _sync());
    _tail = run.catchError((Object _) {});
    return run;
  }

  /// Empties Spotlight of Corplex items and forgets the stamps.
  Future<void> clear() {
    final run = _tail.then((_) async {
      await _channel.clear();
      await _stamps.save({});
    });
    _tail = run.catchError((Object _) {});
    return run;
  }

  Future<Map<String, int>> _currentStamps() async {
    final out = <String, int>{};
    Future<void> read(String prefix, String sql) async {
      for (final r in await _db.customSelect(sql).get()) {
        out['$prefix:${r.read<String>('id')}'] = r.read<int>('stamp');
      }
    }

    await read(
      'note',
      'SELECT id, updated_at * 2 + (content LIKE \'$lockedPrefix%\') AS stamp '
          'FROM notes',
    );
    await read('paper', 'SELECT id, updated_at AS stamp FROM papers');
    await read('project', 'SELECT id, updated_at AS stamp FROM projects');
    return out;
  }

  Future<void> _sync() async {
    var known = await _stamps.load();
    if (known == null) {
      // Nothing recorded: whatever Spotlight holds is of unknown age.
      await _channel.clear();
      known = {};
      await _stamps.save(known);
    }
    final current = await _currentStamps();
    final gone = [
      for (final id in known.keys)
        if (!current.containsKey(id)) id,
    ];
    final changed = [
      for (final e in current.entries)
        if (known[e.key] != e.value) e.key,
    ];
    for (final batch in _batches(gone)) {
      await _channel.remove(batch);
      for (final id in batch) {
        known.remove(id);
      }
      await _stamps.save(known);
      await _yield();
    }
    for (final kind in const ['note', 'paper', 'project']) {
      final ids = [
        for (final key in changed)
          if (key.startsWith('$kind:')) key.substring(kind.length + 1),
      ];
      for (final batch in _batches(ids)) {
        final items = await _load(kind, batch);
        if (items.isNotEmpty) await _channel.index(items);
        for (final id in batch) {
          final key = '$kind:$id';
          if (current[key] case final stamp?) known[key] = stamp;
        }
        await _stamps.save(known);
        await _yield();
      }
    }
  }

  Iterable<List<String>> _batches(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += batchSize) {
      yield ids.sublist(
        i,
        i + batchSize > ids.length ? ids.length : i + batchSize,
      );
    }
  }

  // Lets the UI breathe between batches.
  Future<void> _yield() => Future<void>.delayed(Duration.zero);

  Future<List<SpotlightItem>> _load(String kind, List<String> ids) async {
    final marks = List.filled(ids.length, '?').join(',');
    final vars = [for (final id in ids) Variable.withString(id)];
    switch (kind) {
      case 'note':
        final rows = await _db
            .customSelect(
              'SELECT id, title, aliases, content FROM notes '
              'WHERE id IN ($marks)',
              variables: vars,
            )
            .get();
        return [
          for (final r in rows)
            ?_noteItem(
              r.read<String>('id'),
              r.read<String>('title'),
              r.read<String?>('aliases'),
              r.read<String>('content'),
            ),
        ];
      case 'paper':
        final rows = await _db
            .customSelect(
              'SELECT id, title, authors, year, venue, abstract, citekey '
              'FROM papers WHERE id IN ($marks)',
              variables: vars,
            )
            .get();
        return [
          for (final r in rows)
            _paperItem(
              r.read<String>('id'),
              r.read<String>('title'),
              r.read<String>('authors'),
              r.read<int?>('year'),
              r.read<String?>('venue'),
              r.read<String?>('abstract'),
              r.read<String?>('citekey'),
            ),
        ];
      default:
        final rows = await _db
            .customSelect(
              'SELECT id, name FROM projects WHERE id IN ($marks)',
              variables: vars,
            )
            .get();
        return [
          for (final r in rows)
            SpotlightItem(
              id: 'project:${r.read<String>('id')}',
              title: r.read<String>('name'),
            ),
        ];
    }
  }

  SpotlightItem? _noteItem(
    String id,
    String title,
    String? aliases,
    String content,
  ) {
    final locked = content.startsWith(lockedPrefix);
    var snippet = '';
    if (!locked) {
      try {
        snippet = noteSearchText(content).trim();
      } catch (_) {}
      if (snippet.length > 300) snippet = snippet.substring(0, 300);
    }
    final name = title.trim().isNotEmpty ? title.trim() : null;
    if (name == null && snippet.isEmpty && !locked) return null;
    return SpotlightItem(
      id: 'note:$id',
      title: name ?? (snippet.isEmpty ? untitled : _firstWords(snippet)),
      subtitle: snippet,
      text: snippet,
      keywords: parseAliases(aliases),
    );
  }

  static String _firstWords(String text) =>
      text.length <= 60 ? text : '${text.substring(0, 60)}…';

  SpotlightItem _paperItem(
    String id,
    String title,
    String authors,
    int? year,
    String? venue,
    String? abstract,
    String? citekey,
  ) {
    final byline = [
      if (authors.isNotEmpty) displayAuthors(authors),
      if (venue != null && venue.isNotEmpty) venue,
      ?year?.toString(),
    ].join(' · ');
    return SpotlightItem(
      id: 'paper:$id',
      title: title,
      subtitle: byline,
      text: abstract == null
          ? ''
          : (abstract.length > 800 ? abstract.substring(0, 800) : abstract),
      keywords: [
        if (citekey != null && citekey.isNotEmpty) citekey,
        if (authors.isNotEmpty) authors,
      ],
    );
  }
}
