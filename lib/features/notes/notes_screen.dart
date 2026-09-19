import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'folders_providers.dart';
import 'note_content.dart';
import 'note_editor_screen.dart';
import 'notes_providers.dart';
import 'tags_providers.dart';

/// Distraction-free notes space: quick capture that mixes text, images,
/// and pen input in a single note. Folder/tag filtering only appears once
/// at least one exists, so an unorganized notebook stays uncluttered.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  Future<void> _createNote(BuildContext context, WidgetRef ref) async {
    final id = const Uuid().v4();
    final db = ref.read(databaseProvider);
    final filter = ref.read(notesFilterProvider);
    await db.into(db.notes).insert(
      NotesCompanion.insert(
        id: Value(id),
        folderId: Value(filter is FolderFilter ? filter.folderId : null),
      ),
    );
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
    if (filter is TagFilter) {
      await addTagToNote(db, noteId: id, tagId: filter.tagId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(visibleNotesProvider);
    final foldersAsync = ref.watch(foldersListProvider);
    final tagsAsync = ref.watch(tagsListProvider);
    final showFilterBar =
        (foldersAsync.value?.isNotEmpty ?? false) ||
        (tagsAsync.value?.isNotEmpty ?? false);

    return Scaffold(
      body: Column(
        children: [
          if (showFilterBar)
            _FilterBar(
              folders: foldersAsync.value ?? const [],
              tags: tagsAsync.value ?? const [],
            ),
          Expanded(
            child: notesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) =>
                  Center(child: Text('Something went wrong: $error')),
              data: (notes) {
                if (notes.isEmpty) {
                  return Center(
                    child: Text(
                      'No notes yet.\nTap + to capture your first one.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: notes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return ListTile(
                      title: Text(
                        note.title.isEmpty ? 'Untitled' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        notePlainTextPreview(note.content),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(DateFormat.MMMd().format(note.updatedAt)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NoteEditorScreen(noteId: note.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNote(context, ref),
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.folders, required this.tags});

  final List<Folder> folders;
  final List<Tag> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notesFilterProvider);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('All'),
              selected: filter is AllNotes,
              onSelected: (_) =>
                  ref.read(notesFilterProvider.notifier).state = const AllNotes(),
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
                  label: Text('#${tag.name}'),
                  selected: filter is TagFilter && filter.tagId == tag.id,
                  onSelected: (_) =>
                      ref.read(notesFilterProvider.notifier).state =
                          TagFilter(tag.id),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('New'),
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
      if (ref.read(notesFilterProvider) case FolderFilter(
        folderId: final id,
      ) when id == folder.id) {
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
