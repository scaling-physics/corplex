import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../comments/comments_data.dart';
import 'abbreviations_section.dart';
import 'chapters.dart';
import 'coverage.dart';
import 'open_from_page.dart';
import 'projects_providers.dart' show removeNoteFromProject;
import 'todos.dart';

/// Asks for a submission date (and offers to clear it). Used by the
/// outline header and the project menu.
Future<void> pickProjectDueDate(
  BuildContext context,
  AppDatabase db,
  Project project,
) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: project.dueDate ?? now.add(const Duration(days: 30)),
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 15),
    helpText: 'Submission date',
  );
  if (picked != null) await setProjectDueDate(db, project.id, picked);
}

/// Header lines of the outline: words, chapters final, due date. Nothing
/// at all for a project without notes.
class ChapterHeader extends ConsumerWidget {
  const ChapterHeader({
    super.key,
    required this.project,
    required this.chapters,
  });

  final Project project;
  final List<Chapter> chapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chapters.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final summary = ChapterSummary(chapters);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final due = project.dueDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              summary.wordsLabel,
              if (summary.anyStatus) summary.finishedLabel,
            ].join(' · '),
            key: const ValueKey('chapter-summary'),
            style: style,
          ),
          if (due != null)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final db = ref.read(databaseProvider);
                final action = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.event_outlined),
                          title: const Text('Change date'),
                          onTap: () => Navigator.pop(context, 'change'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.event_busy_outlined),
                          title: const Text('Clear date'),
                          onTap: () => Navigator.pop(context, 'clear'),
                        ),
                      ],
                    ),
                  ),
                );
                if (action == 'clear') {
                  await setProjectDueDate(db, project.id, null);
                } else if (action == 'change' && context.mounted) {
                  await pickProjectDueDate(context, db, project);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  dueLabel(due, DateTime.now()),
                  key: const ValueKey('due-label'),
                  style: style,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The ordered, drag-to-reorder chapter list with its "Add chapter" button.
class ChaptersSection extends ConsumerWidget {
  const ChaptersSection({
    super.key,
    required this.project,
    required this.chapters,
  });

  final Project project;
  final List<Chapter> chapters;

  static bool get _hasHandle => const {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  }.contains(defaultTargetPlatform);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chapters.isEmpty) return const SizedBox.shrink();
    final db = ref.read(databaseProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
          child: Text(
            'Chapters',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            final ids = [for (final c in chapters) c.note.id];
            ids.insert(to, ids.removeAt(from));
            reorderChapters(db, project.id, ids);
          },
          children: [
            for (final (i, c) in chapters.indexed)
              _ChapterRow(
                key: ValueKey('chapter-${c.note.id}'),
                index: i,
                chapter: c,
                projectId: project.id,
                handle: _hasHandle,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add chapter'),
              onPressed: () async {
                final id = await addChapter(db, project.id);
                if (context.mounted) openNoteFromPage(context, ref, id);
              },
            ),
          ),
        ),
        // Each renders nothing when it has nothing to say.
        ProjectTodosSection(
          projectId: project.id,
          orderedNoteIds: [for (final c in chapters) c.note.id],
        ),
        ProjectAbbreviationsSection(projectId: project.id),
        ChapterCoverageSection(
          projectId: project.id,
          orderedNoteIds: [for (final c in chapters) c.note.id],
        ),
      ],
    );
  }
}

class _ChapterRow extends ConsumerWidget {
  const _ChapterRow({
    super.key,
    required this.index,
    required this.chapter,
    required this.projectId,
    required this.handle,
  });

  final int index;
  final Chapter chapter;
  final String projectId;
  final bool handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final db = ref.read(databaseProvider);
    final c = chapter;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final words = c.locked
        ? 'Locked'
        : c.wordTarget == null
        ? '${formatCount(c.words)} words'
        : '${formatCount(c.words)} / ${formatCount(c.wordTarget!)}';

    Widget row = InkWell(
      onTap: () => openNoteFromPage(context, ref, c.note.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PopupMenuButton<Object>(
                        key: ValueKey('status-${c.note.id}'),
                        tooltip: 'Change status',
                        onSelected: (v) => setChapterStatus(
                          db,
                          projectId,
                          c.note.id,
                          v is ChapterStatus ? v : null,
                        ),
                        itemBuilder: (_) => [
                          for (final s in ChapterStatus.values)
                            CheckedPopupMenuItem<Object>(
                              value: s,
                              checked: s == c.status,
                              child: Text(chapterStatusLabel(s)),
                            ),
                          if (c.status != null)
                            const PopupMenuItem<Object>(
                              value: 'none',
                              child: Text('No status'),
                            ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: c.status == null
                                ? null
                                : scheme.secondaryContainer,
                            border: c.status == null
                                ? Border.all(color: scheme.outlineVariant)
                                : null,
                          ),
                          child: Text(
                            c.status == null
                                ? 'Status'
                                : chapterStatusLabel(c.status!),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: c.status == null
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                      Text(words, style: muted),
                      if (ref.watch(openCommentCountsProvider).value?[c.note.id]
                          case final n? when n > 0)
                        InkWell(
                          key: ValueKey('comments-${c.note.id}'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            ref
                                    .read(pendingCommentsPanelProvider.notifier)
                                    .state =
                                c.note.id;
                            openNoteFromPage(context, ref, c.note.id);
                          },
                          child: Text(
                            openCommentsLabel(n),
                            style: muted?.copyWith(color: scheme.tertiary),
                          ),
                        ),
                    ],
                  ),
                  if (c.progress != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        key: ValueKey('progress-${c.note.id}'),
                        value: c.progress,
                        minHeight: 3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('menu-${c.note.id}'),
              tooltip: 'Chapter options',
              onSelected: (v) async {
                if (v == 'target') {
                  final n = await _askTarget(context, c.wordTarget);
                  if (n != null) {
                    await setChapterTarget(db, projectId, c.note.id, n);
                  }
                } else {
                  await removeNoteFromProject(
                    db,
                    projectId: projectId,
                    noteId: c.note.id,
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'target', child: Text('Word target')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from project'),
                ),
              ],
            ),
            if (handle)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
    return ReorderableDelayedDragStartListener(
      key: key,
      index: index,
      child: Material(type: MaterialType.transparency, child: row),
    );
  }
}

/// Returns the new target, 0 to clear it, or null if dismissed.
Future<int?> _askTarget(BuildContext context, int? current) {
  final controller = TextEditingController(text: current?.toString() ?? '');
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Word target'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(hintText: 'e.g. 8000'),
        onSubmitted: (v) => Navigator.pop(context, int.tryParse(v) ?? 0),
      ),
      actions: [
        if (current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(controller.text) ?? 0),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
