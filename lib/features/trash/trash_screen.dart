import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../../data/tables/trash_table.dart';
import '../../data/trash.dart';
import '../../theme/motion_widgets.dart';

/// Deleted notes and papers, restorable for [trashRetention].
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(trashItemsProvider).value ?? const [];
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Empty the trash?'),
                    content: Text(
                      '${items.length} item${items.length == 1 ? '' : 's'} '
                      'will be deleted for good.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Empty'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await purgeTrash(db, all: true);
              },
              child: const Text('Empty'),
            ),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.delete_outline,
              title: 'Trash is empty',
              message:
                  'Deleted notes and papers stay here for '
                  '${trashRetention.inDays} days.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Kept for ${trashRetention.inDays} days, then deleted for good.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final item in items)
                  ListTile(
                    leading: Icon(
                      item.kind == TrashKind.note
                          ? Icons.edit_note_outlined
                          : Icons.article_outlined,
                    ),
                    title: Text(
                      item.title.isEmpty ? 'Untitled' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.kind == TrashKind.note ? 'Note' : 'Paper'} · '
                      '${_daysLeft(item.deletedAt)}',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await restoreFromTrash(db, item.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Restored')),
                          );
                        }
                      },
                      child: const Text('Restore'),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _daysLeft(DateTime deletedAt) {
    final left = trashRetention - DateTime.now().difference(deletedAt);
    final days = left.inDays + (left.inHours % 24 > 0 ? 1 : 0);
    if (days <= 0) return 'deleting soon';
    return '$days day${days == 1 ? '' : 's'} left';
  }
}
