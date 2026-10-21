import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../../theme/context_menu.dart';
import 'saved_searches.dart';

/// Asks for a name (default: the query) and keeps the search. Returns
/// whether it was saved.
Future<bool> saveSearchDialog(
  BuildContext context,
  WidgetRef ref,
  String query,
) async {
  final db = ref.read(databaseProvider);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: context.l10n.savedSearchDialogTitle,
      action: context.l10n.commonSave,
      initial: query.trim(),
    ),
  );
  if (name == null) return false;
  await createSavedSearch(db, name: name, query: query);
  return true;
}

Future<void> renameSearchDialog(
  BuildContext context,
  WidgetRef ref,
  SavedSearchEntry search,
) async {
  final db = ref.read(databaseProvider);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: context.l10n.savedSearchRenameTitle,
      action: context.l10n.commonRename,
      initial: search.name,
    ),
  );
  if (name != null) await renameSavedSearch(db, search.id, name);
}

/// Deletes [search] and offers Undo.
Future<void> deleteSearchWithUndo(
  BuildContext context,
  WidgetRef ref,
  SavedSearchEntry search,
) async {
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  await deleteSavedSearch(db, search.id);
  messenger
    ?..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.savedSearchDeleted(search.name)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => restoreSavedSearch(db, search),
        ),
      ),
    );
}

/// Rename / Delete for a saved search, as a context-menu list (right-click
/// on desktop, also used by the Mac sidebar).
List<ContextMenuAction> savedSearchActions(
  BuildContext context,
  WidgetRef ref,
  SavedSearchEntry search,
) => [
  ContextMenuAction(
    label: context.l10n.savedSearchRename,
    icon: Icons.edit_outlined,
    onSelected: () => renameSearchDialog(context, ref, search),
  ),
  ContextMenuAction(
    label: context.l10n.savedSearchDelete,
    icon: Icons.delete_outline,
    destructive: true,
    onSelected: () => deleteSearchWithUndo(context, ref, search),
  ),
];

/// The saved searches on the empty search screen: tap runs one;
/// long-press or right-click renames or deletes it.
class SavedSearchList extends ConsumerWidget {
  const SavedSearchList({
    super.key,
    required this.searches,
    required this.onRun,
  });

  final List<SavedSearchEntry> searches;
  final ValueChanged<SavedSearchEntry> onRun;

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    SavedSearchEntry s,
  ) async {
    final l10n = context.l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.savedSearchRename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.savedSearchDelete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'rename':
        await renameSearchDialog(context, ref, s);
      case 'delete':
        await deleteSearchWithUndo(context, ref, s);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            context.l10n.savedSearchHeading,
            style: theme.textTheme.titleSmall,
          ),
        ),
        for (final s in searches)
          ContextMenuRegion(
            key: ValueKey('saved-search-${s.id}'),
            actions: savedSearchActions(context, ref, s),
            child: ListTile(
              leading: Icon(
                Icons.bookmark_outline,
                color: theme.colorScheme.primary,
              ),
              title: Text(s.name),
              subtitle: s.name == s.query ? null : Text(s.query),
              onTap: () => onRun(s),
              onLongPress: () => _menu(context, ref, s),
            ),
          ),
      ],
    );
  }
}

/// A quiet "Search tips" line that opens the operator list. Shown on the
/// empty search screen only while there are no saved searches.
class SearchTips extends StatefulWidget {
  const SearchTips({super.key});

  @override
  State<SearchTips> createState() => _SearchTipsState();
}

class _SearchTipsState extends State<SearchTips> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const ValueKey('search-tips'),
            onPressed: () => setState(() => _open = !_open),
            child: Text(context.l10n.savedSearchTipsLink),
          ),
          if (_open)
            Text(
              context.l10n.savedSearchTipsBody,
              key: const ValueKey('search-tips-body'),
              style: muted,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// Owns its text controller so it outlives the dialog's closing animation.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    Navigator.pop(context, text.isEmpty ? widget.initial : text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('saved-search-name'),
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: context.l10n.savedSearchNameLabel),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.commonCancel),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}
