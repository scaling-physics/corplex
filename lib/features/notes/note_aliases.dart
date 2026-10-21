import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import 'notes_providers.dart';

/// Other names a note goes by, stored as `a; b` in `Notes.aliases` (like the
/// study-detail lists). Empty means none.
List<String> parseAliases(String? stored) => [
  for (final part in (stored ?? '').split(';'))
    if (part.trim().isNotEmpty) part.trim(),
];

/// The stored form of [aliases] (null when empty); duplicates are dropped
/// case-insensitively, keeping the first spelling, and `;` can't be part of
/// an alias.
String? formatAliases(Iterable<String> aliases) {
  final seen = <String>{};
  final kept = [
    for (final a in aliases.map((a) => a.replaceAll(';', ',').trim()))
      if (a.isNotEmpty && seen.add(a.toLowerCase())) a,
  ];
  return kept.isEmpty ? null : kept.join('; ');
}

/// Whether [alias] counts for matching (titles and aliases under three
/// characters are too common to be useful).
bool usableName(String name) => name.trim().length >= 3;

Future<void> setNoteAliases(
  AppDatabase db,
  String noteId,
  Iterable<String> aliases,
) => (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
  NotesCompanion(
    aliases: Value(formatAliases(aliases)),
    updatedAt: Value(DateTime.now()),
  ),
);

/// Which alias of [aliases] contains [query] (case-insensitive), if the
/// [title] itself doesn't: the picker then links with the alias as text.
String? matchedAlias(String title, List<String> aliases, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || title.toLowerCase().contains(q)) return null;
  for (final a in aliases) {
    if (a.toLowerCase().contains(q)) return a;
  }
  return null;
}

/// The quiet line under a note's title: "Also: Mice; Mouse model". Nothing
/// when there are no aliases; tap to edit.
class NoteAliasLine extends ConsumerWidget {
  const NoteAliasLine({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases = parseAliases(
      ref.watch(noteByIdProvider(noteId)).value?.aliases,
    );
    if (aliases.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => showAliasesDialog(context, ref, noteId),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            context.l10n.aliasesAlso(aliases.join(', ')),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits a note's aliases: chips with a field to add more. Saved as they
/// change.
Future<void> showAliasesDialog(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) async {
  final db = ref.read(databaseProvider);
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  if (note == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _AliasesDialog(
      initial: parseAliases(note.aliases),
      onChanged: (list) => setNoteAliases(db, noteId, list),
    ),
  );
}

class _AliasesDialog extends StatefulWidget {
  const _AliasesDialog({required this.initial, required this.onChanged});

  final List<String> initial;
  final void Function(List<String>) onChanged;

  @override
  State<_AliasesDialog> createState() => _AliasesDialogState();
}

class _AliasesDialogState extends State<_AliasesDialog> {
  late List<String> _aliases = [...widget.initial];
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _commit(List<String> next) {
    final cleaned = parseAliases(formatAliases(next));
    setState(() => _aliases = cleaned);
    widget.onChanged(cleaned);
  }

  void _add() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    _field.clear();
    _commit([..._aliases, text]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.aliasesTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_aliases.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final a in _aliases)
                      InputChip(
                        label: Text(a),
                        onDeleted: () =>
                            _commit([..._aliases]..removeWhere((x) => x == a)),
                      ),
                  ],
                ),
              ),
            TextField(
              controller: _field,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.aliasesAdd,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.commonAdd,
                  onPressed: _add,
                ),
              ),
              onSubmitted: (_) => _add(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _add();
            Navigator.pop(context);
          },
          child: Text(l10n.commonDone),
        ),
      ],
    );
  }
}
