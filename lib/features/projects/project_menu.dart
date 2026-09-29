import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'projects_providers.dart';

/// Long-press menu on a project chip: rename or delete. Deleting removes
/// only the grouping; its papers and notes are untouched.
Future<void> showProjectMenu(
  BuildContext context,
  WidgetRef ref,
  Project project,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete project'),
            subtitle: const Text('Its papers and notes are kept'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final db = ref.read(databaseProvider);

  if (action == 'rename') {
    final controller = TextEditingController(text: project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await renameProject(db, project.id, name);
    }
  } else {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${project.name}”?'),
        content: const Text(
          'The papers and notes in it stay in your library; only the '
          'grouping goes away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await deleteProject(db, project.id);
  }
}
