import 'dart:convert';

import '../lock/note_crypto.dart' show isLockedContent, isRedactedBase;

/// Three-way merging, for when the same row was edited on two devices
/// between syncs. [base] is the version both edits started from (the last
/// one this device synced), so each side's *changes* can be told apart
/// and kept, instead of one whole version replacing the other.
///
/// Field by field: a field only one side changed takes that change. A note
/// body both sides changed is merged paragraph by paragraph
/// ([mergeNoteContent]); any other field both sides changed keeps the
/// later edit, as before.
Map<String, Object?> mergeRow({
  required String table,
  required List<String> columns,
  required Map<String, Object?> base,
  required Map<String, Object?> local,
  required Map<String, Object?> remote,
}) {
  final localIsLater =
      (local['updated_at']! as int) >= (remote['updated_at']! as int);
  return {
    for (final c in columns)
      c: switch (c) {
        'updated_at' || 'created_at' => local[c],
        _ => _mergeField(
          base[c],
          local[c],
          remote[c],
          both: () {
            // A locked body is an opaque envelope: line-merging it (or
            // mixing it with plain text) would corrupt it, so the later
            // edit wins whole. Same for saved versions.
            if (_isLockedField(base[c], local[c], remote[c])) {
              // Exactly one side locked: the lock wins whatever the
              // timestamps, so a concurrent edit can't undo it.
              final lockedHere = _locked(local[c]);
              final lockedThere = _locked(remote[c]);
              if (lockedHere != lockedThere) {
                return lockedHere ? local[c] : remote[c];
              }
              return localIsLater ? local[c] : remote[c];
            }
            if (table == 'notes' && c == 'content') {
              final merged = mergeNoteContent(
                base[c] as String?,
                local[c] as String?,
                remote[c] as String?,
              );
              if (merged != null) return merged;
            }
            return localIsLater ? local[c] : remote[c];
          },
        ),
      },
  };
}

bool _locked(Object? v) => v is String && isLockedContent(v);

bool _isLockedField(Object? a, Object? b, Object? c) =>
    (a is String && (isLockedContent(a) || isRedactedBase(a))) ||
    (b is String && isLockedContent(b)) ||
    (c is String && isLockedContent(c));

Object? _mergeField(
  Object? base,
  Object? local,
  Object? remote, {
  required Object? Function() both,
}) {
  if (local == remote) return local;
  if (local == base) return remote;
  if (remote == base) return local;
  return both();
}

/// Merges two edits of a note body (Quill Delta JSON) made from [base].
/// Works on lines — paragraphs, headings, list items, each with its
/// formatting — so edits to different paragraphs both survive. Where both
/// sides changed the same paragraph differently, both versions are kept,
/// this device's first: nothing anyone wrote is lost. Returns null when a
/// body isn't Delta JSON (e.g. a very old plain-text note).
String? mergeNoteContent(String? base, String? local, String? remote) {
  final b = _lines(base), l = _lines(local), r = _lines(remote);
  if (b == null || l == null || r == null) return null;
  final merged = merge3(b, l, r);
  return jsonEncode(_joinLines(merged));
}

/// The ops of a Delta, split into lines: each ends with its "\n" op (which
/// carries the line's block format), so a line compares equal only if its
/// text, inline formats and block format all match. Lines are encoded as
/// JSON strings for cheap comparison.
List<String>? _lines(String? content) {
  if (content == null) return null;
  final Object? ops;
  try {
    ops = jsonDecode(content);
  } on FormatException {
    return null;
  }
  if (ops is! List) return null;

  final lines = <String>[];
  var current = <Map<String, Object?>>[];
  void close() {
    lines.add(jsonEncode(current));
    current = [];
  }

  for (final op in ops) {
    if (op is! Map) return null;
    final insert = op['insert'];
    final attributes = op['attributes'];
    Map<String, Object?> make(Object? value) => {
      'insert': value,
      'attributes': ?attributes,
    };
    if (insert is! String) {
      current.add(make(insert));
      continue;
    }
    final parts = insert.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) current.add(make(parts[i]));
      if (i < parts.length - 1) {
        current.add(make('\n'));
        close();
      }
    }
  }
  if (current.isNotEmpty) close();
  return lines;
}

/// Rejoins lines into Delta ops, merging neighbouring text runs that share
/// formatting, and making sure the document ends with a newline as Quill
/// requires.
List<Map<String, Object?>> _joinLines(List<String> lines) {
  final ops = <Map<String, Object?>>[];
  for (final line in lines) {
    for (final op in (jsonDecode(line) as List).cast<Map<String, Object?>>()) {
      final last = ops.isEmpty ? null : ops.last;
      if (last != null &&
          last['insert'] is String &&
          op['insert'] is String &&
          jsonEncode(last['attributes']) == jsonEncode(op['attributes'])) {
        ops[ops.length - 1] = {
          ...last,
          'insert': '${last['insert']}${op['insert']}',
        };
      } else {
        ops.add(op);
      }
    }
  }
  final end = ops.isEmpty ? null : ops.last['insert'];
  if (end is! String || !end.endsWith('\n')) ops.add({'insert': '\n'});
  return ops;
}

/// A change one side made to the base: base lines [start, end) became
/// [lines].
class _Hunk {
  _Hunk(this.start, this.end, this.lines, {required this.local});

  final int start;
  final int end;
  final List<String> lines;
  final bool local;
}

/// Three-way merge of line lists (diff3). Changes to different parts of
/// [base] are all applied; where [local] and [remote] changed the same part
/// differently, both versions are kept, [local]'s first.
List<String> merge3(
  List<String> base,
  List<String> local,
  List<String> remote,
) {
  final hunks =
      [..._diff(base, local, local: true), ..._diff(base, remote, local: false)]
        ..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.end.compareTo(b.end);
        });

  final out = <String>[];
  var pos = 0;
  var i = 0;
  while (i < hunks.length) {
    // Gather every hunk touching the same stretch of base. Changes that
    // merely sit next to each other (one ends where the other starts) are
    // independent and stay apart.
    final group = [hunks[i]];
    final start = hunks[i].start;
    var end = hunks[i].end;
    i++;
    while (i < hunks.length &&
        (hunks[i].start < end || hunks[i].start == start)) {
      if (hunks[i].end > end) end = hunks[i].end;
      group.add(hunks[i]);
      i++;
    }

    out.addAll(base.sublist(pos, start));
    final mine = _apply(base, start, end, group.where((h) => h.local));
    final theirs = _apply(base, start, end, group.where((h) => !h.local));
    if (group.every((h) => h.local)) {
      out.addAll(mine);
    } else if (group.every((h) => !h.local)) {
      out.addAll(theirs);
    } else if (_same(mine, theirs)) {
      out.addAll(mine);
    } else {
      out
        ..addAll(mine)
        ..addAll(theirs);
    }
    pos = end;
  }
  out.addAll(base.sublist(pos));
  return out;
}

/// base[start, end) with [hunks] (all inside it, in order) applied.
List<String> _apply(
  List<String> base,
  int start,
  int end,
  Iterable<_Hunk> hunks,
) {
  final out = <String>[];
  var pos = start;
  for (final h in hunks) {
    out
      ..addAll(base.sublist(pos, h.start))
      ..addAll(h.lines);
    pos = h.end;
  }
  out.addAll(base.sublist(pos, end));
  return out;
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The changes turning [base] into [other], via a longest common
/// subsequence of lines.
List<_Hunk> _diff(
  List<String> base,
  List<String> other, {
  required bool local,
}) {
  // Most edits touch a small part of a note: skip the common ends first.
  var prefix = 0;
  while (prefix < base.length &&
      prefix < other.length &&
      base[prefix] == other[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < base.length - prefix &&
      suffix < other.length - prefix &&
      base[base.length - 1 - suffix] == other[other.length - 1 - suffix]) {
    suffix++;
  }
  final n = base.length - prefix - suffix;
  final m = other.length - prefix - suffix;
  if (n == 0 && m == 0) return const [];

  // Matched (base index, other index) pairs, in order.
  final matches = <(int, int)>[];
  // A huge rewrite isn't worth a quadratic table: treat it as one change.
  if (n > 0 && m > 0 && n * m <= 4000000) {
    final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var x = n - 1; x >= 0; x--) {
      for (var y = m - 1; y >= 0; y--) {
        table[x][y] = base[prefix + x] == other[prefix + y]
            ? table[x + 1][y + 1] + 1
            : (table[x + 1][y] >= table[x][y + 1]
                  ? table[x + 1][y]
                  : table[x][y + 1]);
      }
    }
    var x = 0, y = 0;
    while (x < n && y < m) {
      if (base[prefix + x] == other[prefix + y]) {
        matches.add((prefix + x, prefix + y));
        x++;
        y++;
      } else if (table[x + 1][y] >= table[x][y + 1]) {
        x++;
      } else {
        y++;
      }
    }
  }

  final hunks = <_Hunk>[];
  var bi = prefix, oi = prefix;
  for (final (mb, mo) in [...matches, (prefix + n, prefix + m)]) {
    if (mb > bi || mo > oi) {
      hunks.add(_Hunk(bi, mb, other.sublist(oi, mo), local: local));
    }
    bi = mb + 1;
    oi = mo + 1;
  }
  return hunks;
}
