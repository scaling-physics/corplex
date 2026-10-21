import '../../l10n/l10n.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../lock/note_lock_service.dart';
import '../projects/readable_content.dart';
import 'editor_document.dart';
import 'note_aliases.dart';
import 'note_links.dart';
import 'note_sections.dart';

/// What the note picker returned: a note, optionally one heading or
/// paragraph of it. [title] is the text to show for the link (the alias it
/// was found by, "Title › Heading" for a part).
class NoteLinkPick {
  const NoteLinkPick({
    required this.id,
    required this.title,
    this.heading,
    this.block,
  });

  final String id;
  final String title;
  final String? heading;
  final String? block;

  String get link => noteLink(id, heading: heading, block: block);
}

/// The note being edited, so `[[#Heading]]` and `[[#^` can name its own
/// parts. The editor owns its live document; a block id for it is written
/// into that document, never the database.
class LiveNote {
  const LiveNote({
    required this.noteId,
    required this.title,
    required this.document,
    required this.assignBlockId,
  });

  final String noteId;
  final String title;

  /// The note as the editor shows it, with every section unfolded.
  final Document Function() document;

  /// Marks the line starting at the offset with a block id (reusing one it
  /// has) and returns it.
  final String Function(int lineStart) assignBlockId;
}

enum LinkPart { none, heading, block }

/// What was typed into the picker: `Title`, `Title#Head` (a heading of that
/// note) or `Title#^text` (a paragraph).
class LinkQuery {
  const LinkQuery(this.title, this.part, this.filter);

  final String title;
  final LinkPart part;
  final String filter;
}

LinkQuery parseLinkQuery(String raw) {
  final at = raw.indexOf('#');
  if (at < 0) return LinkQuery(raw.trim(), LinkPart.none, '');
  final title = raw.substring(0, at).trim();
  var rest = raw.substring(at + 1);
  if (rest.startsWith('^')) {
    return LinkQuery(title, LinkPart.block, rest.substring(1).trim());
  }
  return LinkQuery(title, LinkPart.heading, rest.trim());
}

/// Searchable picker for linking to (or embedding) another note, or part of
/// one. Returns the chosen (or newly created) note, or null if dismissed.
Future<NoteLinkPick?> showNoteLinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required String excludeNoteId,
  LiveNote? live,
  bool embed = false,
}) {
  return showModalBottomSheet<NoteLinkPick>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _NoteLinkSheet(excludeNoteId: excludeNoteId, live: live, embed: embed),
  );
}

class _NoteLinkSheet extends ConsumerStatefulWidget {
  const _NoteLinkSheet({
    required this.excludeNoteId,
    required this.live,
    required this.embed,
  });

  final String excludeNoteId;
  final LiveNote? live;
  final bool embed;

  @override
  ConsumerState<_NoteLinkSheet> createState() => _NoteLinkSheetState();
}

class _NoteLinkSheetState extends ConsumerState<_NoteLinkSheet> {
  final _field = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _set(String text) {
    _field.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _query = text);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseLinkQuery(_query);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _field,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: widget.embed
                        ? context.l10n.linksEmbedANote
                        : context.l10n.notesLinkToANote,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Flexible(
                child: parsed.part == LinkPart.none
                    ? _NoteList(
                        query: parsed.title,
                        excludeNoteId: widget.excludeNoteId,
                        embed: widget.embed,
                        onDrill: (title) => _set('$title#'),
                      )
                    : _PartList(
                        query: parsed,
                        live: widget.live,
                        onRetype: _set,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteList extends ConsumerWidget {
  const _NoteList({
    required this.query,
    required this.excludeNoteId,
    required this.embed,
    required this.onDrill,
  });

  final String query;
  final String excludeNoteId;
  final bool embed;
  final void Function(String title) onDrill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final notes =
        (db.select(db.notes)
              ..where((n) => n.id.equals(excludeNoteId).not())
              ..where(
                (n) => query.isEmpty
                    ? const Constant(true)
                    : n.title.like('%$query%') | n.aliases.like('%$query%'),
              )
              ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
              ..limit(30))
            .watch();
    return StreamBuilder<List<Note>>(
      stream: notes,
      builder: (context, snapshot) {
        final found = snapshot.data ?? const <Note>[];
        return ListView(
          shrinkWrap: true,
          children: [
            if (!embed &&
                query.isNotEmpty &&
                !found.any((n) => n.title.toLowerCase() == query.toLowerCase()))
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(context.l10n.notesNewNoteNamed(query)),
                onTap: () async {
                  final id = const Uuid().v4();
                  await db
                      .into(db.notes)
                      .insert(
                        NotesCompanion.insert(
                          id: Value(id),
                          title: Value(query),
                        ),
                      );
                  if (context.mounted) {
                    Navigator.pop(context, NoteLinkPick(id: id, title: query));
                  }
                },
              ),
            for (final n in found) _noteTile(context, n),
          ],
        );
      },
    );
  }

  Widget _noteTile(BuildContext context, Note n) {
    final title = n.title.isEmpty ? context.l10n.commonUntitled : n.title;
    final alias = matchedAlias(n.title, parseAliases(n.aliases), query);
    return ListTile(
      leading: const Icon(Icons.edit_note_outlined),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: alias == null
          ? null
          : Text(alias, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Into the note: its headings (and, with ^, paragraphs).
      trailing: n.title.trim().isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.tag, size: 20),
              tooltip: context.l10n.linksHeadingsOf,
              onPressed: () => onDrill(n.title),
            ),
      onTap: () =>
          Navigator.pop(context, NoteLinkPick(id: n.id, title: alias ?? title)),
    );
  }
}

/// A note's headings or paragraphs, once the query has a `#`.
class _PartList extends ConsumerStatefulWidget {
  const _PartList({
    required this.query,
    required this.live,
    required this.onRetype,
  });

  final LinkQuery query;
  final LiveNote? live;
  final void Function(String text) onRetype;

  @override
  ConsumerState<_PartList> createState() => _PartListState();
}

class _PartData {
  const _PartData({
    required this.noteId,
    required this.title,
    required this.lines,
    required this.live,
    this.unreadable = false,
    this.lockedBody,
  });

  final String noteId;
  final String title;
  final List<DocLine> lines;
  final bool live;
  final bool unreadable;
  final bool? lockedBody;
}

class _PartListState extends ConsumerState<_PartList> {
  Future<_PartData?>? _data;
  String? _forTitle;

  Future<_PartData?> _load(String title) async {
    final live = widget.live;
    if (title.isEmpty) {
      if (live == null) return null;
      return _PartData(
        noteId: live.noteId,
        title: live.title,
        lines: docLines(live.document().toDelta()),
        live: true,
      );
    }
    final db = ref.read(databaseProvider);
    final lower = title.toLowerCase();
    final all = await (db.select(
      db.notes,
    )..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])).get();
    Note? exact;
    Note? partial;
    for (final n in all) {
      final names = [n.title, ...parseAliases(n.aliases)];
      if (names.any((x) => x.toLowerCase() == lower)) {
        exact ??= n;
      } else if (names.any((x) => x.toLowerCase().contains(lower))) {
        partial ??= n;
      }
    }
    final note = exact ?? partial;
    if (note == null) return null;
    if (live != null && note.id == live.noteId) {
      return _PartData(
        noteId: note.id,
        title: note.title,
        lines: docLines(live.document().toDelta()),
        live: true,
      );
    }
    final lock = ref.read(noteLockServiceProvider);
    final body = await readableNoteContent(lock, note.id, note.content);
    if (body == null) {
      return _PartData(
        noteId: note.id,
        title: note.title,
        lines: const [],
        live: false,
        unreadable: true,
      );
    }
    return _PartData(
      noteId: note.id,
      title: note.title,
      lines: docLines(editorDocument(body).toDelta()),
      live: false,
      lockedBody: isLockedContent(note.content),
    );
  }

  Future<void> _pickBlock(_PartData data, DocLine line) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    String? id = line.blockId;
    if (id == null) {
      if (data.live) {
        id = widget.live!.assignBlockId(line.start);
      } else {
        final lock = ref.read(noteLockServiceProvider);
        id = await assignBlockIdInNote(
          db,
          data.noteId,
          line.start,
          decrypt: data.lockedBody == true
              ? (content) => lock.decryptBody(data.noteId, content)
              : null,
          encrypt: data.lockedBody == true
              ? (body) => lock.encryptBody(data.noteId, body)
              : null,
        );
      }
    }
    if (!mounted) return;
    if (id == null) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.linksParagraphUnavailable)),
      );
      return;
    }
    Navigator.pop(
      context,
      NoteLinkPick(
        id: data.noteId,
        title: partLinkText(data.title, line.text),
        block: id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    if (_forTitle != q.title) {
      _forTitle = q.title;
      _data = _load(q.title);
    }
    return FutureBuilder<_PartData?>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 80);
        }
        if (data == null) return const SizedBox(height: 80);
        final l10n = context.l10n;
        final filter = q.filter.toLowerCase();
        final shownTitle = data.title.isEmpty
            ? l10n.commonUntitled
            : data.title;
        if (data.unreadable) {
          return ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(shownTitle),
                subtitle: Text(l10n.linksPartsLocked),
                onTap: () => Navigator.pop(
                  context,
                  NoteLinkPick(id: data.noteId, title: shownTitle),
                ),
              ),
            ],
          );
        }
        final children = <Widget>[
          // The whole note stays one tap away.
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: Text(
              shownTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.pop(
              context,
              NoteLinkPick(id: data.noteId, title: shownTitle),
            ),
          ),
        ];
        if (q.part == LinkPart.heading) {
          final headings = [
            for (final h in headingsOf(data.lines))
              if (filter.isEmpty || h.text.toLowerCase().contains(filter)) h,
          ];
          for (final h in headings) {
            children.add(
              ListTile(
                contentPadding: EdgeInsets.only(
                  left: 16.0 + 16 * (h.level - 1),
                  right: 16,
                ),
                leading: const Icon(Icons.tag, size: 20),
                title: Text(
                  h.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(
                  context,
                  NoteLinkPick(
                    id: data.noteId,
                    title: partLinkText(data.title, h.text),
                    heading: h.text,
                  ),
                ),
              ),
            );
          }
          if (headings.isEmpty && filter.isEmpty) {
            children.add(
              ListTile(enabled: false, title: Text(l10n.linksNoHeadings)),
            );
          }
          children.add(
            ListTile(
              leading: const Icon(Icons.format_align_left),
              title: Text(l10n.linksToParagraph),
              subtitle: Text(l10n.linksToParagraphHint),
              onTap: () => widget.onRetype('${data.title}#^'),
            ),
          );
        } else {
          final paragraphs = [
            for (final l in paragraphsOf(data.lines))
              if (filter.isEmpty || l.text.toLowerCase().contains(filter)) l,
          ];
          for (final l in paragraphs) {
            children.add(
              ListTile(
                leading: const Icon(Icons.short_text),
                title: Text(
                  l.text.replaceAll('￼', ' ').trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: l.blockId == null
                    ? null
                    : Text(
                        '^${l.blockId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                onTap: () => _pickBlock(data, l),
              ),
            );
          }
          if (paragraphs.isEmpty && filter.isEmpty) {
            children.add(
              ListTile(enabled: false, title: Text(l10n.linksNoParagraphs)),
            );
          }
        }
        return ListView(shrinkWrap: true, children: children);
      },
    );
  }
}
