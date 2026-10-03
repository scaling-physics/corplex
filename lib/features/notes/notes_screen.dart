import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../home/getting_started.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'folders_providers.dart';
import 'note_content.dart';
import '../home/adaptive.dart';
import 'notes_providers.dart';
import 'tags_providers.dart';
import '../../theme/swipe_to_trash.dart';
import '../projects/project_menu.dart';
import '../trash/trash_actions.dart';
import '../projects/projects_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion_widgets.dart';

/// Creates an empty note (filed into whatever folder/tag is being viewed,
/// so it doesn't vanish from the list) and opens it. Used by the home
/// screen's "New note" button.
Future<void> createNote(BuildContext context, WidgetRef ref) async {
  final id = const Uuid().v4();
  final db = ref.read(databaseProvider);
  final filter = ref.read(notesFilterProvider);
  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          folderId: Value(filter is FolderFilter ? filter.folderId : null),
        ),
      );
  if (!context.mounted) return;
  openNote(context, ref, id);
  if (filter is TagFilter) {
    await addTagToNote(db, noteId: id, tagId: filter.tagId);
  }
  // A note started while viewing a project belongs to it.
  if (filter is ProjectFilter) {
    await addNoteToProject(db, noteId: id, projectId: filter.projectId);
  }
}

/// Distraction-free notes space: quick capture that mixes text, images,
/// and pen input in a single note. Folder/tag filtering only appears once
/// at least one exists, so an unorganized notebook stays uncluttered.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(visibleNotesProvider);
    final foldersAsync = ref.watch(foldersListProvider);
    final tagsAsync = ref.watch(tagsListProvider);
    final folders = foldersAsync.value ?? const <Folder>[];
    final projects = ref.watch(projectsListProvider).value ?? const <Project>[];
    final showFilterBar =
        folders.isNotEmpty ||
        (tagsAsync.value?.isNotEmpty ?? false) ||
        projects.isNotEmpty;
    final filter = ref.watch(notesFilterProvider);
    final folderNames = {for (final f in folders) f.id: f.name};

    return Column(
      children: [
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: showFilterBar
              ? _FilterBar(
                  folders: folders,
                  tags: tagsAsync.value ?? const [],
                  projects: projects,
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: StateSwitcher(
            stateKey: switch (notesAsync) {
              AsyncData(value: []) => 'empty',
              AsyncData() => filter,
              AsyncError() => 'error',
              _ => 'loading',
            },
            child: notesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) =>
                  Center(child: Text('Something went wrong: $error')),
              data: (notes) {
                if (notes.isEmpty) {
                  if (filter is AllNotes && ref.watch(isFreshStartProvider)) {
                    return const GettingStarted();
                  }
                  return filter is AllNotes
                      ? const EmptyState(
                          icon: Icons.edit_note_outlined,
                          title: 'No notes yet',
                          message:
                              'Tap New note to capture your first thought.',
                        )
                      : const EmptyState(
                          icon: Icons.filter_list,
                          title: 'Nothing here yet',
                          message: 'Notes you add while this filter is on land here.',
                        );
                }
                return ListView.separated(
                  // Clear of the floating "New note" button.
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: notes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return EntranceTransition(
                      key: ValueKey(note.id),
                      index: index,
                      child: SwipeToTrash(
                        dismissKey: ValueKey('swipe-${note.id}'),
                        onTrash: () => deleteNoteWithUndo(
                          ref,
                          ScaffoldMessenger.of(context),
                          note.id,
                          note.title,
                        ),
                        child: _NoteCard(
                          note: note,
                          // The folder is redundant while filtering by it.
                          folderName: filter is FolderFilter
                              ? null
                              : folderNames[note.folderId],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note, required this.folderName});

  final Note note;
  final String? folderName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final preview = notePlainTextPreview(note.content);
    final meta = theme.textTheme.labelMedium?.copyWith(
      color: c.onSurfaceVariant,
    );

    // In the tablet layout, the note open beside the list is marked.
    final selected =
        hasDetailPane(context) && ref.watch(selectedNoteProvider) == note.id;
    return Card(
      color: selected ? c.secondaryContainer : null,
      child: InkWell(
        onTap: () => openNote(context, ref, note.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.title.isEmpty ? 'Untitled' : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: note.title.isEmpty ? c.onSurfaceVariant : null,
                ),
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(_friendlyDate(note.updatedAt), style: meta),
                  if (folderName case final name?) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.folder_outlined, size: 14, color: c.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta?.copyWith(color: c.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _friendlyDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today, ${DateFormat.jm().format(date)}';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.EEEE().format(date);
    if (date.year == now.year) return DateFormat.MMMd().format(date);
    return DateFormat.yMMMd().format(date);
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.folders,
    required this.tags,
    required this.projects,
  });

  final List<Folder> folders;
  final List<Tag> tags;
  final List<Project> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notesFilterProvider);

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('All'),
              selected: filter is AllNotes,
              onSelected: (_) => ref.read(notesFilterProvider.notifier).state =
                  const AllNotes(),
            ),
          ),
          for (final project in projects)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onLongPress: () => showProjectMenu(context, ref, project),
                child: ChoiceChip(
                  avatar: const Icon(Icons.folder_special_outlined, size: 18),
                  label: Text(project.name),
                  selected:
                      filter is ProjectFilter && filter.projectId == project.id,
                  onSelected: (_) =>
                      ref.read(notesFilterProvider.notifier).state =
                          ProjectFilter(project.id),
                ),
              ),
            ),
          for (final folder in folders)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onLongPress: () => _confirmDeleteFolder(context, ref, folder),
                child: ChoiceChip(
                  avatar: const Icon(Icons.folder_outlined, size: 18),
                  label: Text(folder.name),
                  selected:
                      filter is FolderFilter && filter.folderId == folder.id,
                  onSelected: (_) =>
                      ref.read(notesFilterProvider.notifier).state =
                          FolderFilter(folder.id),
                ),
              ),
            ),
          for (final tag in tags)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onLongPress: () => _confirmDeleteTag(context, ref, tag),
                child: ChoiceChip(
                  avatar: const Icon(Icons.tag, size: 16),
                  label: Text(tag.name),
                  selected: filter is TagFilter && filter.tagId == tag.id,
                  onSelected: (_) =>
                      ref.read(notesFilterProvider.notifier).state = TagFilter(
                        tag.id,
                      ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Folder or tag'),
              onPressed: () => _showCreateSheet(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteFolder(
    BuildContext context,
    WidgetRef ref,
    Folder folder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: const Text('Notes inside will be unfiled, not deleted.'),
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
    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      if (ref.read(notesFilterProvider) case FolderFilter(folderId: final id)
          when id == folder.id) {
        ref.read(notesFilterProvider.notifier).state = const AllNotes();
      }
      await deleteFolder(db, folder.id);
    }
  }

  Future<void> _confirmDeleteTag(
    BuildContext context,
    WidgetRef ref,
    Tag tag,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "#${tag.name}"?'),
        content: const Text('This removes the tag from every note.'),
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
    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      if (ref.read(notesFilterProvider) case TagFilter(tagId: final id)
          when id == tag.id) {
        ref.read(notesFilterProvider.notifier).state = const AllNotes();
      }
      await deleteTag(db, tag.id);
    }
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('New folder'),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('New tag'),
              onTap: () => Navigator.pop(context, 'tag'),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !context.mounted) return;

    final name = await _promptForName(context, kind);
    if (name == null || name.trim().isEmpty) return;

    final db = ref.read(databaseProvider);
    if (kind == 'folder') {
      final id = await createFolder(db, name.trim());
      ref.read(notesFilterProvider.notifier).state = FolderFilter(id);
    } else {
      final id = await findOrCreateTag(db, name.trim());
      ref.read(notesFilterProvider.notifier).state = TagFilter(id);
    }
  }

  Future<String?> _promptForName(BuildContext context, String kind) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(kind == 'folder' ? 'New folder' : 'New tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: kind == 'folder' ? 'Folder name' : 'Tag name',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
