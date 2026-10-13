import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../export/export_actions.dart';
import '../export/export_model.dart';
import 'abbreviations.dart' show abbreviationBlocks;
import 'chapters.dart';
import 'chapters_section.dart' show pickProjectDueDate;
import 'matrix_screen.dart';
import 'project_bibliography.dart';
import 'project_page.dart';
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open project'),
              subtitle: const Text('Its papers, notes and reading progress'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Synthesis matrix'),
              subtitle: const Text('Compare its papers by theme'),
              onTap: () => Navigator.pop(context, 'matrix'),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Bibliography'),
              subtitle: const Text('All its papers, in a citation style'),
              onTap: () => Navigator.pop(context, 'bibliography'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export project'),
              subtitle: const Text('Its notes as one document'),
              onTap: () => Navigator.pop(context, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(
                project.dueDate == null ? 'Set due date' : 'Change due date',
              ),
              subtitle: const Text('The submission date'),
              onTap: () => Navigator.pop(context, 'due'),
            ),
            if (project.dueDate != null)
              ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('Clear due date'),
                onTap: () => Navigator.pop(context, 'clear-due'),
              ),
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
    await exportProject(context, db, project);
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

/// Exports every note in [project] as one document in chapter order, under
/// one reference list.
Future<void> exportProject(
  BuildContext context,
  AppDatabase db,
  Project project,
) async {
  final notes = await orderedProjectNotes(db, project.id);
  if (!context.mounted) return;
  if (notes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No notes in this project yet.')),
    );
    return;
  }
  await exportNotes(
    context,
    db,
    [for (final n in notes) ExportNote(n.title, n.content)],
    title: project.name,
    extraFrontMatter: abbreviationBlocks([for (final n in notes) n.content]),
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
  controller.dispose();
  if (name != null && name.trim().isNotEmpty) {
    await renameProject(db, project.id, name);
  }
}
