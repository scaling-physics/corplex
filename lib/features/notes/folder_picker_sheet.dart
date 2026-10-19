import '../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import 'folders_providers.dart';

Future<void> showFolderPickerSheet(
  BuildContext context,
  WidgetRef ref,
  String noteId,
  String? currentFolderId,
) {
  return showModalBottomSheet(
    context: context,
    builder: (_) =>
        _FolderPickerSheet(noteId: noteId, currentFolderId: currentFolderId),
  );
}

class _FolderPickerSheet extends ConsumerWidget {
  const _FolderPickerSheet({
    required this.noteId,
    required this.currentFolderId,
  });

  final String noteId;
  final String? currentFolderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersListProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(context.l10n.notesNoFolder),
            trailing: currentFolderId == null ? const Icon(Icons.check) : null,
            onTap: () => _select(context, ref, null),
          ),
          ...switch (foldersAsync.value) {
            null => const [],
            final folders => folders.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                trailing: currentFolderId == folder.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => _select(context, ref, folder.id),
              ),
            ),
          },
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(context.l10n.notesNewFolder),
            onTap: () => _createAndSelect(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    String? folderId,
  ) async {
    await setNoteFolder(
      ref.read(databaseProvider),
      noteId: noteId,
      folderId: folderId,
    );
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _createAndSelect(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.notesNewFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: dialogContext.l10n.notesFolderName,
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(dialogContext.l10n.notesCreate),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final db = ref.read(databaseProvider);
    final id = await createFolder(db, name.trim());
    if (!context.mounted) return;
    await _select(context, ref, id);
  }
}
