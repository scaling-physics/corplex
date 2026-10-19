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
import '../../l10n/l10n.dart';
import 'note_file_actions.dart' show duplicateNoteAndOpen;
import 'note_lock_actions.dart' show lockNoteFromList, removeLockFromList;
import '../home/adaptive.dart';
import '../home/mac_sidebar.dart' show DraggedNote, macSidebarVisibleProvider;
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

/// The group a note sits under in the list, as in Apple Notes: Pinned,
/// Today, Yesterday, Previous 7 Days, Previous 30 Days, then the month
/// (this year) or the year. Lists are ordered pinned first, then newest
/// edit, so each group is one run.
String noteDateSection(NoteListItem note, DateTime now, AppLocalizations l10n) {
  if (note.pinned) return l10n.listPinned;
  final d = note.updatedAt;
  // Calendar days, immune to a daylight-saving hour.
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (days <= 0) return l10n.listToday;
  if (days == 1) return l10n.listYesterday;
  if (days < 7) return l10n.listPrevious7Days;
  if (days < 30) return l10n.listPrevious30Days;
  if (d.year == now.year) return DateFormat.MMMM(l10n.localeName).format(d);
  return '${d.year}';
}

/// For each note, the group header to show above it (null when it is in
/// the same group as the note before).
List<String?> noteSectionHeaders(
  List<NoteListItem> notes,
  DateTime now,
  AppLocalizations l10n,
) {
  String? previous;
  return [
    for (final n in notes)
      () {
        final section = noteDateSection(n, now, l10n);
        final header = section == previous ? null : section;
        previous = section;
        return header;
      }(),
  ];
}

/// A group header in the Notes list.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {required this.first, required this.mac});

  final String label;
  final bool first;
  final bool mac;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: mac
          ? EdgeInsets.fromLTRB(12, first ? 6 : 18, 12, 4)
          : EdgeInsets.fromLTRB(4, first ? 4 : 10, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: mac
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
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
    // On a Mac the sidebar lists folders, projects and tags, as in Notes.
    final sidebarFilters =
        isDesktop(context) && ref.watch(macSidebarVisibleProvider);
    final showFilterBar =
        !sidebarFilters &&
        (folders.isNotEmpty ||
            (tagsAsync.value?.isNotEmpty ?? false) ||
            projects.isNotEmpty);
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
                error: (error, _) => Center(
                  child: Text(context.l10n.listSomethingWentWrong('$error')),
                ),
                data: (notes) {
                  if (notes.isEmpty) {
                    if (filter is AllNotes && ref.watch(isFreshStartProvider)) {
                      return const GettingStarted();
                    }
                    return filter is AllNotes
                        ? EmptyState(
                            icon: Icons.edit_note_outlined,
                            title: context.l10n.listNoNotesTitle,
                            message: context.l10n.listNoNotesMessage,
                          )
                        : EmptyState(
                            icon: Icons.filter_list,
                            title: context.l10n.listNothingHereTitle,
                            message: context.l10n.listNothingHereMessage,
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
                  final headers = noteSectionHeaders(
                    notes,
                    DateTime.now(),
                    context.l10n,
                  );
                  return NewItemScope(
                    ids: [for (final n in notes) n.id],
                    child: ListView.separated(
                      // Clear of the floating "New note" button.
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: notes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        final card = SwipeToTrash(
                          dismissKey: ValueKey('swipe-${note.id}'),
                          onTrash: () => deleteNoteWithUndo(
                            ref,
                            ScaffoldMessenger.of(context),
                            note.id,
                            note.title,
                            l10n: context.l10n,
                          ),
                          child: _NoteCard(
                            note: note,
                            // The folder is redundant while filtering by it.
                            folderName: filter is FolderFilter
                                ? null
                                : folderNames[note.folderId],
                          ),
                        );
                        return ListItemMotion(
                          key: ValueKey(note.id),
                          id: note.id,
                          index: index,
                          child: headers[index] == null
                              ? card
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _SectionHeader(
                                      headers[index]!,
                                      first: index == 0,
                                      mac: false,
                                    ),
                                    card,
                                  ],
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
    l10n: context.l10n,
  );
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note, required this.folderName});

  final NoteListItem note;
  final String? folderName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final l10n = context.l10n;
    final locked = note.locked;
    final preview = note.preview;
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
                  TextSpan(
                    text: note.title.isEmpty ? l10n.commonUntitled : note.title,
                  ),
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
                l10n.commonLocked,
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
                Text(_friendlyDate(context, note.updatedAt), style: meta),
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
      actions: _noteMenuActions(
        context,
        ref,
        note,
        onOpen: () => openNote(context, ref, note.id),
      ),
      child: card,
    );
  }

  static String _friendlyDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat.jm(locale).format(date); // under "Today"
    if (diff == 1) return context.l10n.listYesterday;
    if (diff < 7) return DateFormat.EEEE(locale).format(date);
    if (date.year == now.year) return DateFormat.MMMd(locale).format(date);
    return DateFormat.yMMMd(locale).format(date);
  }
}

/// The right-click items for a list row. The lock and duplicate actions
/// load the note itself only when chosen, so the list never holds bodies.
List<ContextMenuAction?> _noteMenuActions(
  BuildContext context,
  WidgetRef ref,
  NoteListItem note, {
  required VoidCallback onOpen,
}) {
  final l10n = context.l10n;
  return [
    ContextMenuAction(
      label: l10n.commonOpen,
      icon: Icons.open_in_new,
      onSelected: onOpen,
    ),
    ContextMenuAction(
      label: l10n.listAddToProject,
      icon: Icons.folder_special_outlined,
      onSelected: () => showProjectPickerSheet(context, noteId: note.id),
    ),
    ContextMenuAction(
      label: note.locked ? l10n.listRemoveLock : l10n.listLockNote,
      icon: note.locked ? Icons.lock_open_outlined : Icons.lock_outline,
      onSelected: () async {
        final full = await ref
            .read(databaseProvider)
            .managers
            .notes
            .filter((f) => f.id.equals(note.id))
            .getSingleOrNull();
        if (full == null || !context.mounted) return;
        if (note.locked) {
          await removeLockFromList(context, ref, full);
        } else {
          await lockNoteFromList(context, ref, full);
        }
      },
    ),
    ContextMenuAction(
      label: note.pinned ? l10n.listUnpin : l10n.listPinToTop,
      icon: note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
      onSelected: () =>
          setNotePinned(ref.read(databaseProvider), note.id, !note.pinned),
    ),
    ContextMenuAction(
      label: l10n.listDuplicate,
      icon: Icons.copy_outlined,
      onSelected: () => duplicateNoteAndOpen(context, ref, note.id),
    ),
    null,
    ContextMenuAction(
      label: l10n.commonMoveToTrash,
      icon: Icons.delete_outline,
      destructive: true,
      onSelected: () => deleteNoteWithUndo(
        ref,
        ScaffoldMessenger.of(context),
        note.id,
        note.title,
        l10n: context.l10n,
      ),
    ),
  ];
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
              label: Text(context.l10n.listAll),
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
                onLongPress: () => confirmDeleteFolder(context, ref, folder),
                onSecondaryTapUp: isDesktop(context)
                    ? (d) => showContextMenuAt(context, d.globalPosition, [
                        ContextMenuAction(
                          label: context.l10n.listDeleteFolderEllipsis,
                          icon: Icons.delete_outline,
                          destructive: true,
                          onSelected: () =>
                              confirmDeleteFolder(context, ref, folder),
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
                onLongPress: () => confirmDeleteTag(context, ref, tag),
                onSecondaryTapUp: isDesktop(context)
                    ? (d) => showContextMenuAt(context, d.globalPosition, [
                        ContextMenuAction(
                          label: context.l10n.listDeleteTagEllipsis,
                          icon: Icons.delete_outline,
                          destructive: true,
                          onSelected: () => confirmDeleteTag(context, ref, tag),
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
              label: Text(context.l10n.listFolderOrTag),
              onPressed: () => showCreateFolderOrTagSheet(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks to delete [folder]; its notes are unfiled, not deleted.
Future<void> confirmDeleteFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.listDeleteFolderTitle(folder.name)),
      content: Text(context.l10n.listDeleteFolderMessage),
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
  if (confirmed == true) {
    final db = ref.read(databaseProvider);
    if (ref.read(notesFilterProvider) case FolderFilter(folderId: final id)
        when id == folder.id) {
      ref.read(notesFilterProvider.notifier).state = const AllNotes();
    }
    await deleteFolder(db, folder.id);
  }
}

Future<void> confirmDeleteTag(
  BuildContext context,
  WidgetRef ref,
  Tag tag,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.listDeleteTagTitle(tag.name)),
      content: Text(context.l10n.listDeleteTagMessage),
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
  if (confirmed == true) {
    final db = ref.read(databaseProvider);
    if (ref.read(notesFilterProvider) case TagFilter(tagId: final id)
        when id == tag.id) {
      ref.read(notesFilterProvider.notifier).state = const AllNotes();
    }
    await deleteTag(db, tag.id);
  }
}

Future<void> showCreateFolderOrTagSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(context.l10n.listNewFolder),
            onTap: () => Navigator.pop(context, 'folder'),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: Text(context.l10n.listNewTag),
            onTap: () => Navigator.pop(context, 'tag'),
          ),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;

  final name = await promptForName(context, kind);
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

Future<String?> promptForName(BuildContext context, String kind) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        kind == 'folder' ? context.l10n.listNewFolder : context.l10n.listNewTag,
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: kind == 'folder'
              ? context.l10n.listFolderName
              : context.l10n.listTagName,
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(context.l10n.listCreate),
        ),
      ],
    ),
  );
}

/// The Notes list on a Mac: Apple Notes-style rows, focusable, ↑/↓ moves the
/// selection (opening that note in the pane at once), Return or Tab moves
/// the keyboard into the open note.
class _MacNotesList extends ConsumerStatefulWidget {
  const _MacNotesList({required this.notes, required this.folderNames});

  final List<NoteListItem> notes;
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
    final headers = noteSectionHeaders(notes, DateTime.now(), context.l10n);
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
            final locked = note.locked;
            final preview = note.preview;
            final folder = widget.folderNames[note.folderId];
            final row = KeyedSubtree(
              key: _keys.putIfAbsent(note.id, GlobalKey.new),
              child: ContextMenuRegion(
                actions: _noteMenuActions(
                  context,
                  ref,
                  note,
                  onOpen: () => _select(note.id),
                ),
                child: MacListRow(
                  selected: note.id == selectedId,
                  listFocused: _focus.hasFocus,
                  showDivider:
                      index < notes.length - 1 && headers[index + 1] == null,
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
                          text: note.title.isEmpty
                              ? context.l10n.commonUntitled
                              : note.title,
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
                          text: _NoteCard._friendlyDate(
                            context,
                            note.updatedAt,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (locked)
                          TextSpan(
                            text: '  ${context.l10n.commonLocked}',
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
            );
            // Drag a note onto a folder, project or tag in the sidebar.
            final draggable = Draggable<DraggedNote>(
              data: DraggedNote(note.id, note.title),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _DragChip(
                title: note.title.isEmpty
                    ? context.l10n.commonUntitled
                    : note.title,
              ),
              childWhenDragging: Opacity(opacity: 0.5, child: row),
              child: row,
            );
            return ListItemMotion(
              key: ValueKey(note.id),
              id: note.id,
              index: index,
              child: headers[index] == null
                  ? draggable
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          headers[index]!,
                          first: index == 0,
                          mac: true,
                        ),
                        draggable,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// What follows the pointer while a note is dragged to the sidebar.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
