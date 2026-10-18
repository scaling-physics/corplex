import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../home/getting_started.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'folders_providers.dart';
import '../lock/note_lock_service.dart' show isLockedContent;
import 'note_content.dart';
import 'note_lock_actions.dart';
import '../home/adaptive.dart';
import '../home/open_card.dart';
import 'note_editor_screen.dart'
    show NoteEditorScreen, noteBodyFocusRequestProvider;
import 'notes_providers.dart';
import 'tags_providers.dart';
import '../../theme/context_menu.dart';
import '../../theme/swipe_to_trash.dart';
import '../../theme/mac_list_row.dart';
import '../platform/mac_window.dart'
    show MenuCommand, MenuCommandHandler, isDesktop, isMac;
import '../projects/project_picker_sheet.dart';
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

    return _TrashShortcut(
      child: Column(
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
                  if (isDesktop(context)) {
                    return _MacNotesList(
                      notes: notes,
                      folderNames: filter is FolderFilter
                          ? const {}
                          : folderNames,
                    );
                  }
                  return NewItemScope(
                    ids: [for (final n in notes) n.id],
                    child: ListView.separated(
                      // Clear of the floating "New note" button.
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: notes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return ListItemMotion(
                          key: ValueKey(note.id),
                          id: note.id,
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
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// File → Move to Trash (⌘⌫) while the list has focus: the note open in the
/// detail pane goes to the trash with Undo. The Mac embedder offers ⌘⌫ to
/// Flutter first, and a focused text field takes it (delete to line start),
/// so only an unhandled one reaches the menu and then this handler.
class _TrashShortcut extends ConsumerWidget {
  const _TrashShortcut({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isMac(context)) return child;
    return MenuCommandHandler(
      commands: {
        MenuCommand.moveToTrash: () {
          final id = ref.read(selectedNoteProvider);
          if (id != null && hasDetailPane(context)) _trash(context, ref, id);
        },
      },
      child: child,
    );
  }
}

Future<void> _trash(BuildContext context, WidgetRef ref, String id) async {
  final note = await ref
      .read(databaseProvider)
      .managers
      .notes
      .filter((f) => f.id.equals(id))
      .getSingleOrNull();
  if (!context.mounted) return;
  await deleteNoteWithUndo(
    ref,
    ScaffoldMessenger.of(context),
    id,
    note?.title ?? '',
  );
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note, required this.folderName});

  final Note note;
  final String? folderName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final locked = isLockedContent(note.content);
    final preview = locked ? '' : notePlainTextPreview(note.content);
    final meta = theme.textTheme.labelMedium?.copyWith(
      color: c.onSurfaceVariant,
    );

    // In the tablet layout, the note open beside the list is marked.
    final selected =
        hasDetailPane(context) && ref.watch(selectedNoteProvider) == note.id;
    final desktop = isDesktop(context);
    final card = OpenCard(
      selected: selected,
      onOpenInPane: () => openNote(context, ref, note.id),
      pageBuilder: (_) => NoteEditorScreen(noteId: note.id),
      child: Padding(
        padding: desktop
            ? const EdgeInsets.fromLTRB(14, 10, 14, 9)
            : const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  if (note.pinned)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.push_pin, size: 15, color: c.primary),
                      ),
                    ),
                  TextSpan(text: note.title.isEmpty ? 'Untitled' : note.title),
                  if (locked)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: note.title.isEmpty ? c.onSurfaceVariant : null,
              ),
            ),
            if (locked) ...[
              SizedBox(height: desktop ? 2 : 4),
              Text(
                'Locked',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: c.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else if (preview.isNotEmpty) ...[
              SizedBox(height: desktop ? 2 : 4),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: c.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: desktop ? 6 : 10),
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
    );
    if (!desktop) return card;
    return ContextMenuRegion(
      actions: [
        ContextMenuAction(
          label: 'Open',
          icon: Icons.open_in_new,
          onSelected: () => openNote(context, ref, note.id),
        ),
        ContextMenuAction(
          label: 'Add to project…',
          icon: Icons.folder_special_outlined,
          onSelected: () => showProjectPickerSheet(context, noteId: note.id),
        ),
        lockMenuAction(context, ref, note),
        pinMenuAction(ref, note),
        null,
        ContextMenuAction(
          label: 'Move to trash',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () => deleteNoteWithUndo(
            ref,
            ScaffoldMessenger.of(context),
            note.id,
            note.title,
          ),
        ),
      ],
      child: card,
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
                onSecondaryTap: isDesktop(context)
                    ? () => showProjectMenu(context, ref, project)
                    : null,
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
                onSecondaryTapUp: isDesktop(context)
                    ? (d) => showContextMenuAt(context, d.globalPosition, [
                        ContextMenuAction(
                          label: 'Delete folder…',
                          icon: Icons.delete_outline,
                          destructive: true,
                          onSelected: () =>
                              _confirmDeleteFolder(context, ref, folder),
                        ),
                      ])
                    : null,
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
                onSecondaryTapUp: isDesktop(context)
                    ? (d) => showContextMenuAt(context, d.globalPosition, [
                        ContextMenuAction(
                          label: 'Delete tag…',
                          icon: Icons.delete_outline,
                          destructive: true,
                          onSelected: () =>
                              _confirmDeleteTag(context, ref, tag),
                        ),
                      ])
                    : null,
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

/// The Notes list on a Mac: Apple Notes-style rows, focusable, ↑/↓ moves the
/// selection (opening that note in the pane at once), Return or Tab moves
/// the keyboard into the open note.
class _MacNotesList extends ConsumerStatefulWidget {
  const _MacNotesList({required this.notes, required this.folderNames});

  final List<Note> notes;
  final Map<String, String> folderNames;

  @override
  ConsumerState<_MacNotesList> createState() => _MacNotesListState();
}

class _MacNotesListState extends ConsumerState<_MacNotesList> {
  final _focus = FocusNode(debugLabel: 'notes list');
  final _keys = <String, GlobalKey>{};

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _select(String id) {
    openNote(context, ref, id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _keys[id]?.currentContext;
      if (row != null && row.mounted) {
        Scrollable.ensureVisible(
          row,
          duration: const Duration(milliseconds: 90),
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (meta || !hasDetailPane(context) || widget.notes.isEmpty) {
        return KeyEventResult.ignored;
      }
      final ids = [for (final n in widget.notes) n.id];
      final at = ids.indexOf(ref.read(selectedNoteProvider) ?? '');
      final next = key == LogicalKeyboardKey.arrowDown
          ? (at < 0 ? 0 : (at + 1).clamp(0, ids.length - 1))
          : (at < 0 ? 0 : (at - 1).clamp(0, ids.length - 1));
      _select(ids[next]);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.tab) &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !meta) {
      if (ref.read(selectedNoteProvider) == null) {
        return KeyEventResult.ignored;
      }
      ref.read(noteBodyFocusRequestProvider.notifier).state++;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    final selectedId = hasDetailPane(context)
        ? ref.watch(selectedNoteProvider)
        : null;
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return NewItemScope(
      ids: [for (final n in notes) n.id],
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        onFocusChange: (_) => setState(() {}),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            final locked = isLockedContent(note.content);
            final preview = locked ? '' : notePlainTextPreview(note.content);
            final folder = widget.folderNames[note.folderId];
            return ListItemMotion(
              key: ValueKey(note.id),
              id: note.id,
              index: index,
              child: KeyedSubtree(
                key: _keys.putIfAbsent(note.id, GlobalKey.new),
                child: ContextMenuRegion(
                  actions: [
                    ContextMenuAction(
                      label: 'Open',
                      icon: Icons.open_in_new,
                      onSelected: () => _select(note.id),
                    ),
                    ContextMenuAction(
                      label: 'Add to project…',
                      icon: Icons.folder_special_outlined,
                      onSelected: () =>
                          showProjectPickerSheet(context, noteId: note.id),
                    ),
                    lockMenuAction(context, ref, note),
                    pinMenuAction(ref, note),
                    null,
                    ContextMenuAction(
                      label: 'Move to trash',
                      icon: Icons.delete_outline,
                      destructive: true,
                      onSelected: () => deleteNoteWithUndo(
                        ref,
                        ScaffoldMessenger.of(context),
                        note.id,
                        note.title,
                      ),
                    ),
                  ],
                  child: MacListRow(
                    selected: note.id == selectedId,
                    listFocused: _focus.hasFocus,
                    showDivider: index < notes.length - 1,
                    onTap: () {
                      _focus.requestFocus();
                      _select(note.id);
                    },
                    title: Text.rich(
                      TextSpan(
                        children: [
                          if (note.pinned)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Icon(
                                  Icons.push_pin,
                                  size: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          TextSpan(
                            text: note.title.isEmpty ? 'Untitled' : note.title,
                          ),
                          if (locked)
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(left: 5),
                                child: Icon(Icons.lock_outline, size: 13),
                              ),
                            ),
                        ],
                      ),
                      style: note.title.isEmpty
                          ? TextStyle(color: c.onSurfaceVariant)
                          : null,
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _NoteCard._friendlyDate(note.updatedAt),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (locked)
                            const TextSpan(
                              text: '  Locked',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            )
                          else if (preview.isNotEmpty)
                            TextSpan(text: '  $preview'),
                        ],
                      ),
                    ),
                    trailing: folder == null
                        ? null
                        : Tooltip(
                            message: folder,
                            child: Icon(
                              Icons.folder_outlined,
                              size: 14,
                              color: c.primary,
                            ),
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
