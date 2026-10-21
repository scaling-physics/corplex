import '../../l10n/l10n.dart';
import '../export/export_images.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../export/export_actions.dart';
import '../export/export_model.dart';
import '../export/unlock_for_export.dart';
import '../lock/note_lock_service.dart';
import 'abbreviations.dart' show abbreviationBlocks;
import 'chapters.dart';
import 'chapters_section.dart' show pickProjectDueDate;
import 'matrix_screen.dart';
import 'project_bibliography.dart';
import 'project_page.dart';
import 'projects_providers.dart';
import 'readable_content.dart';

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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(context.l10n.projectsOpenProject),
              subtitle: Text(context.l10n.projectsOpenProjectSubtitle),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(context.l10n.projectsSynthesisMatrix),
              subtitle: Text(context.l10n.projectsSynthesisMatrixSubtitle),
              onTap: () => Navigator.pop(context, 'matrix'),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: Text(context.l10n.projectsBibliography),
              subtitle: Text(context.l10n.projectsBibliographySubtitle),
              onTap: () => Navigator.pop(context, 'bibliography'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(context.l10n.projectsExportProject),
              subtitle: Text(context.l10n.projectsExportProjectSubtitle),
              onTap: () => Navigator.pop(context, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(
                project.dueDate == null
                    ? context.l10n.projectsSetDueDate
                    : context.l10n.projectsChangeDueDate,
              ),
              subtitle: Text(context.l10n.projectsSubmissionDateSubtitle),
              onTap: () => Navigator.pop(context, 'due'),
            ),
            if (project.dueDate != null)
              ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: Text(context.l10n.projectsClearDueDate),
                onTap: () => Navigator.pop(context, 'clear-due'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.l10n.commonRename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.projectsDeleteProject),
              subtitle: Text(context.l10n.projectsDeleteProjectSubtitle),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final db = ref.read(databaseProvider);

  if (action == 'open') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectScreen(projectId: project.id),
      ),
    );
    return;
  }
  if (action == 'matrix') {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MatrixScreen(project: project)));
    return;
  }
  if (action == 'due') {
    await pickProjectDueDate(context, db, project);
    return;
  }
  if (action == 'clear-due') {
    await setProjectDueDate(db, project.id, null);
    return;
  }
  if (action == 'export') {
    await exportProject(context, ref, project);
    return;
  }
  if (action == 'bibliography') {
    await shareProjectBibliography(context, ref, project);
    return;
  }

  if (action == 'rename') {
    await renameProjectDialog(context, db, project);
  } else {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.projectsDeleteTitle(project.name)),
        content: Text(context.l10n.projectsDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) await deleteProject(db, project.id);
  }
}

/// Exports every note in [project] as one document in chapter order, under
/// one reference list.
///
/// Locked chapters are decrypted for the export (the reader is asked to
/// unlock first); declining cancels it rather than silently leaving
/// chapters out.
Future<void> exportProject(
  BuildContext context,
  WidgetRef ref,
  Project project,
) async {
  final db = ref.read(databaseProvider);
  final lock = ref.read(noteLockServiceProvider);
  final notes = await orderedProjectNotes(db, project.id);
  if (!context.mounted) return;
  if (notes.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.projectsNoNotesYet)));
    return;
  }
  if (notes.any(
    (n) => isLockedContent(n.content) && !lock.canRead(n.content),
  )) {
    final ok = await requestUnlock(
      context,
      lock,
      reason: context.l10n.projectsChaptersLockedReason,
    );
    if (!ok || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.projectsExportCancelledLocked)),
        );
      }
      return;
    }
  }
  final contents = <String>[];
  for (final n in notes) {
    final text = await readableNoteContent(lock, n.id, n.content);
    // Still unreadable (damaged, or locked again meanwhile): title only.
    contents.add(text ?? '');
  }
  final images = [
    for (final (i, n) in notes.indexed)
      // Pictures only with a readable body.
      contents[i].isEmpty ? <ExportImage>[] : await noteExportImages(db, n.id),
  ];
  if (!context.mounted) return;
  await exportNotes(
    context,
    db,
    [
      for (final (i, n) in notes.indexed)
        ExportNote(n.title, contents[i], images: images[i], id: n.id),
    ],
    title: project.name,
    extraFrontMatter: abbreviationBlocks(contents),
  );
}

/// Asks for a new name for [project] and saves it.
Future<void> renameProjectDialog(
  BuildContext context,
  AppDatabase db,
  Project project,
) async {
  final controller = TextEditingController(text: project.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.projectsRenameProject),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(context.l10n.commonSave),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name != null && name.trim().isNotEmpty) {
    await renameProject(db, project.id, name);
  }
}
