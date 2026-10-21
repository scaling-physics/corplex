import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../lock/note_crypto.dart' show isLockedContent;
import '../search/search_index.dart';
import 'note_aliases.dart';
import 'note_content.dart';
import 'note_links.dart';
import 'notes_providers.dart';

/// A place in a note's text that names another note without linking to it.
class Mention {
  const Mention({
    required this.start,
    required this.length,
    required this.name,
    required this.snippet,
  });

  /// Offset in the note's document (an embed is one character).
  final int start;
  final int length;

  /// The title or alias that matched, as written in the text.
  final String name;

  /// The words around it.
  final String snippet;

  int get end => start + length;
}

final _wordPattern = RegExp(r'[\p{L}\p{N}_]', unicode: true);

/// Whether the UTF-16 unit at [i] belongs to a word (surrogate halves are
/// treated as letters, so a name next to an astral letter doesn't match).
bool _isWord(String s, int i) {
  final unit = s.codeUnitAt(i);
  if (unit >= 0xD800 && unit <= 0xDFFF) return true;
  return _wordPattern.hasMatch(s[i]);
}

/// The first whole-word, case-insensitive occurrence in [delta] of any of
/// [names] that isn't already part of a link. Names under three characters
/// are ignored. Text is the document's: embeds count as one character and
/// never match.
Mention? findUnlinkedMention(Delta delta, Iterable<String> names) {
  final wanted = [
    for (final n in names)
      if (usableName(n)) n.trim(),
  ]..sort((a, b) => b.length.compareTo(a.length));
  if (wanted.isEmpty) return null;
  final text = StringBuffer();
  final linked = <bool>[];
  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    final data = op.data;
    final isLinked = op.attributes?.containsKey('link') == true;
    if (data is String) {
      text.write(data);
      for (var i = 0; i < data.length; i++) {
        linked.add(isLinked);
      }
    } else {
      text.write('￼');
      linked.add(true);
    }
  }
  final plain = text.toString();
  final lower = plain.toLowerCase();
  // Lowercasing can change a string's length for a few scripts; then the
  // offsets can't be trusted and the note is left alone.
  if (lower.length != plain.length) return null;
  Mention? best;
  for (final name in wanted) {
    final needle = name.toLowerCase();
    var from = 0;
    while (true) {
      final at = lower.indexOf(needle, from);
      if (at < 0) break;
      from = at + 1;
      final end = at + needle.length;
      if (best != null && at >= best.start) break;
      if (at > 0 && _isWord(plain, at - 1)) continue;
      if (end < plain.length && _isWord(plain, end)) continue;
      var clear = true;
      for (var i = at; i < end; i++) {
        if (linked[i]) {
          clear = false;
          break;
        }
      }
      if (!clear) continue;
      best = Mention(
        start: at,
        length: needle.length,
        name: plain.substring(at, end),
        snippet: _snippet(plain, at, end),
      );
      break;
    }
  }
  return best;
}

String _snippet(String plain, int start, int end) {
  final from = (start - 48).clamp(0, plain.length);
  final to = (end + 64).clamp(0, plain.length);
  final text = plain
      .substring(from, to)
      .replaceAll('￼', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return '${from > 0 ? '…' : ''}$text${to < plain.length ? '…' : ''}';
}

/// A note that mentions another without linking to it.
class UnlinkedMention {
  const UnlinkedMention({
    required this.noteId,
    required this.title,
    required this.mention,
  });

  final String noteId;
  final String title;
  final Mention mention;
}

/// The notes that name [noteId] (by its title or an alias) without linking
/// to it. Candidates come from the full-text index; each is checked here
/// for a whole-word match outside links. Not the note itself, not notes
/// that already link here, not locked notes.
Future<List<UnlinkedMention>> findUnlinkedMentions(
  AppDatabase db,
  SearchIndex index,
  String noteId, {
  int limit = 25,
}) async {
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  if (note == null) return const [];
  final names = [
    note.title,
    ...parseAliases(note.aliases),
  ].where(usableName).toList();
  if (names.isEmpty) return const [];

  final ids = <String>{};
  for (final name in names) {
    final words = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(name).map((m) => m.group(0)!).toList();
    if (words.isEmpty) continue;
    final hits = await index.search(words.join(' '), limit: 80);
    for (final h in hits) {
      if (h.kind == SearchKind.note && !h.locked && h.id != noteId) {
        ids.add(h.id);
      }
    }
  }
  if (ids.isEmpty) return const [];
  final rows =
      await (db.select(db.notes)
            ..where((n) => n.id.isIn(ids))
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
          .get();
  final link = noteLink(noteId);
  final out = <UnlinkedMention>[];
  for (final n in rows) {
    if (isLockedContent(n.content) || n.content.contains(link)) continue;
    final mention = findUnlinkedMention(
      decodeNoteContent(n.content).toDelta(),
      names,
    );
    if (mention == null) continue;
    out.add(UnlinkedMention(noteId: n.id, title: n.title, mention: mention));
    if (out.length >= limit) break;
  }
  return out;
}

/// Turns the first unlinked mention of [targetId] in note [inNoteId] into a
/// link to it, keeping the text as written. False when there is nothing to
/// link any more (changed, locked, deleted).
Future<bool> linkFirstMention(
  AppDatabase db, {
  required String inNoteId,
  required String targetId,
}) async {
  final target = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(targetId))).getSingleOrNull();
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(inNoteId))).getSingleOrNull();
  if (target == null || note == null || isLockedContent(note.content)) {
    return false;
  }
  final document = decodeNoteContent(note.content);
  final mention = findUnlinkedMention(document.toDelta(), [
    target.title,
    ...parseAliases(target.aliases),
  ]);
  if (mention == null) return false;
  document.format(
    mention.start,
    mention.length,
    LinkAttribute(noteLink(targetId)),
  );
  await (db.update(db.notes)..where((n) => n.id.equals(inNoteId))).write(
    NotesCompanion(
      content: Value(encodeNoteContent(document)),
      updatedAt: Value(DateTime.now()),
    ),
  );
  return true;
}

/// Refreshes when the note's name changes or a note starts linking here.
final unlinkedMentionsProvider = FutureProvider.autoDispose
    .family<List<UnlinkedMention>, String>((ref, noteId) {
      ref.watch(
        noteByIdProvider(noteId)
            .select((v) => (v.value?.title, v.value?.aliases)),
      );
      ref.watch(backlinksProvider(noteId));
      return findUnlinkedMentions(
        ref.watch(databaseProvider),
        ref.watch(searchIndexProvider),
        noteId,
      );
    });

/// "Unlinked mentions (3)", under "Linked from": a collapsed row that opens
/// the notes naming this one in plain text, each with a Link button. Nothing
/// at all when there are none.
class UnlinkedMentionsSection extends ConsumerStatefulWidget {
  const UnlinkedMentionsSection({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<UnlinkedMentionsSection> createState() =>
      _UnlinkedMentionsSectionState();
}

class _UnlinkedMentionsSectionState
    extends ConsumerState<UnlinkedMentionsSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final mentions =
        ref.watch(unlinkedMentionsProvider(widget.noteId)).value ?? const [];
    if (mentions.isEmpty) return const SizedBox(width: double.infinity);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.linksUnlinkedMentions(mentions.length),
                    style: theme.textTheme.titleSmall,
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            for (final m in mentions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  m.title.isEmpty ? l10n.commonUntitled : m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  m.mention.snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final db = ref.read(databaseProvider);
                    await linkFirstMention(
                      db,
                      inNoteId: m.noteId,
                      targetId: widget.noteId,
                    );
                    ref.invalidate(unlinkedMentionsProvider(widget.noteId));
                  },
                  child: Text(l10n.linksLinkMention),
                ),
              ),
        ],
      ),
    );
  }
}
