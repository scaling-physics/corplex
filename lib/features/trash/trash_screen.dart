import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/adaptive.dart' show ReadableColumn;

import '../../data/database_provider.dart';
import '../../data/tables/trash_table.dart';
import '../../data/trash.dart';
import '../../l10n/l10n.dart';
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
        title: Text(context.l10n.commonTrash),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(context.l10n.trashEmptyTitle),
                    content: Text(context.l10n.trashEmptyBody(items.length)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(context.l10n.commonCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(context.l10n.trashEmptyAction),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await purgeTrash(db, all: true);
              },
              child: Text(context.l10n.trashEmptyAction),
            ),
        ],
      ),
      body: ReadableColumn(
        child: items.isEmpty
            ? EmptyState(
                icon: Icons.delete_outline,
                title: context.l10n.trashIsEmpty,
                message: context.l10n.trashEmptyMessage(trashRetention.inDays),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      context.l10n.trashKept(trashRetention.inDays),
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
                        item.title.isEmpty
                            ? context.l10n.commonUntitled
                            : item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.kind == TrashKind.note ? context.l10n.trashKindNote : context.l10n.trashKindPaper} · '
                        '${_daysLeft(context.l10n, item.deletedAt)}',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await restoreFromTrash(db, item.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.l10n.trashRestored),
                              ),
                            );
                          }
                        },
                        child: Text(context.l10n.trashRestore),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  static String _daysLeft(AppLocalizations l10n, DateTime deletedAt) {
    final left = trashRetention - DateTime.now().difference(deletedAt);
    final days = left.inDays + (left.inHours % 24 > 0 ? 1 : 0);
    if (days <= 0) return l10n.trashDeletingSoon;
    return l10n.trashDaysLeft(days);
  }
}
