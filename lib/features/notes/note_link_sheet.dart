import '../../l10n/l10n.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

/// Searchable picker for linking to another note. Returns the chosen (or
/// newly created) note's id and title, or null if dismissed.
Future<({String id, String title})?> showNoteLinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required String excludeNoteId,
}) {
  return showModalBottomSheet<({String id, String title})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NoteLinkSheet(excludeNoteId: excludeNoteId),
  );
}

class _NoteLinkSheet extends ConsumerStatefulWidget {
  const _NoteLinkSheet({required this.excludeNoteId});

  final String excludeNoteId;

  @override
  ConsumerState<_NoteLinkSheet> createState() => _NoteLinkSheetState();
}

class _NoteLinkSheetState extends ConsumerState<_NoteLinkSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final query = _query.trim();
    final notes =
        (db.select(db.notes)
              ..where((n) => n.id.equals(widget.excludeNoteId).not())
              ..where(
                (n) => query.isEmpty
                    ? const Constant(true)
                    : n.title.like('%$query%'),
              )
              ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
              ..limit(30))
            .watch();

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
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: context.l10n.notesLinkToANote,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Flexible(
                child: StreamBuilder<List<Note>>(
                  stream: notes,
                  builder: (context, snapshot) {
                    final found = snapshot.data ?? const <Note>[];
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        if (query.isNotEmpty &&
                            !found.any(
                              (n) =>
                                  n.title.toLowerCase() == query.toLowerCase(),
                            ))
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
                                Navigator.pop(context, (id: id, title: query));
                              }
                            },
                          ),
                        for (final n in found)
                          ListTile(
                            leading: const Icon(Icons.edit_note_outlined),
                            title: Text(
                              n.title.isEmpty
                                  ? context.l10n.commonUntitled
                                  : n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, (
                              id: n.id,
                              title: n.title.isEmpty
                                  ? context.l10n.commonUntitled
                                  : n.title,
                            )),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
