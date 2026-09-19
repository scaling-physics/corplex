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
    builder: (_) => _FolderPickerSheet(
      noteId: noteId,
      currentFolderId: currentFolderId,
    ),
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
            title: const Text('No folder'),
            trailing: currentFolderId == null
                ? const Icon(Icons.check)
                : null,
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
            title: const Text('New folder'),
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
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Create'),
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
