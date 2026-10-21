import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../l10n/l10n.dart';
import 'daily_settings.dart';
import 'folders_providers.dart';
import 'templates.dart';

/// Settings → Daily notes: one row that opens a small dialog with the
/// template and the folder new daily notes use (per device).
class DailyNotesSettingsTile extends ConsumerWidget {
  const DailyNotesSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.today_outlined),
      title: Text(l10n.dailySettingsTitle),
      subtitle: Text(l10n.dailySettingsSubtitle),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const _DailySettingsDialog(),
      ),
    );
  }
}

class _DailySettingsDialog extends ConsumerWidget {
  const _DailySettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(dailyNoteSettingsProvider);
    final templates = ref.watch(templateNotesProvider).value ?? const <Note>[];
    final folders = ref.watch(foldersListProvider).value ?? const <Folder>[];
    // A choice whose note or folder is gone reads as "None".
    final templateId = templates.any((t) => t.id == settings.templateId)
        ? settings.templateId
        : null;
    final folderId = folders.any((f) => f.id == settings.folderId)
        ? settings.folderId
        : null;
    return AlertDialog(
      title: Text(l10n.dailySettingsTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.dailyTemplate),
            DropdownButton<String?>(
              key: const ValueKey('daily-template'),
              isExpanded: true,
              value: templateId,
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.dailyNone)),
                for (final t in templates)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      templateLabel(t, l10n),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: settings.setTemplate,
            ),
            if (templates.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.dailyTemplateHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            Text(l10n.dailyFolder),
            DropdownButton<String?>(
              key: const ValueKey('daily-folder'),
              isExpanded: true,
              value: folderId,
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.dailyNone)),
                for (final f in folders)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text(f.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: settings.setFolder,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonDone),
        ),
      ],
    );
  }
}
