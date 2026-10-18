import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/context_menu.dart';
import '../notes/folders_providers.dart';
import '../notes/notes_providers.dart';
import '../notes/notes_screen.dart' show confirmDeleteFolder, confirmDeleteTag;
import '../notes/tags_providers.dart';
import '../projects/project_menu.dart' show showProjectMenu;
import '../../theme/app_theme.dart';
import '../attachments/attachments_browser.dart';
import '../projects/project_page.dart';
import '../projects/projects_providers.dart';
import '../sync/sync_ring.dart';

/// Whether the Mac sidebar is showing (View > Toggle Sidebar). Per session.
final macSidebarVisibleProvider = StateProvider<bool>((ref) => true);

/// Width of the sidebar.
const macSidebarWidth = 232.0;

/// The Mac list column's width bounds and default.
const macListMinWidth = 280.0;
const macListMaxWidth = 520.0;
const macListDefaultWidth = 340.0;

/// How wide the list column is, which the reader sets by dragging its
/// divider. Remembered per device (shared_preferences, not synced) and
/// loaded after startup; [macListDefaultWidth] until then.
class MacListWidth extends ChangeNotifier {
  MacListWidth({bool load = true}) {
    if (load) _load();
  }

  static const _key = 'mac.listWidth';
  double _width = macListDefaultWidth;
  bool _touched = false;

  double get width => _width;

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getDouble(_key);
      if (saved != null && !_touched) {
        _width = saved.clamp(macListMinWidth, macListMaxWidth);
        notifyListeners();
      }
    } catch (_) {}
  }

  void set(double value) {
    _touched = true;
    final next = value.clamp(macListMinWidth, macListMaxWidth);
    if (next == _width) return;
    _width = next;
    notifyListeners();
  }

  Future<void> save() async {
    try {
      await (await SharedPreferences.getInstance()).setDouble(_key, _width);
    } catch (_) {}
  }
}

final macListWidthProvider = ChangeNotifierProvider<MacListWidth>(
  (ref) => MacListWidth(),
);

/// Slides the sidebar in and out (instantly under reduced motion). While
/// fully hidden it builds nothing, so it can't take focus or clicks.
class MacSidebarSlot extends StatelessWidget {
  const MacSidebarSlot({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.medium),
      curve: AppMotion.standard,
      child: child,
      builder: (context, t, child) {
        if (t == 0) return const SizedBox.shrink();
        return ClipRect(
          child: SizedBox(
            width: (macSidebarWidth + 1) * t,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              // The sidebar plus the 1 pt line the shell draws beside it.
              minWidth: macSidebarWidth + 1,
              maxWidth: macSidebarWidth + 1,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// A draggable divider between two columns. Reports horizontal drags.
class ColumnDivider extends StatefulWidget {
  const ColumnDivider({
    super.key,
    required this.onDrag,
    required this.onDragEnd,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  @override
  State<ColumnDivider> createState() => _ColumnDividerState();
}

class _ColumnDividerState extends State<ColumnDivider> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _active = false);
          widget.onDragEnd();
        },
        child: SizedBox(
          width: 7,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.short),
              width: _active ? 3 : 1,
              color: _active
                  ? c.primary.withValues(alpha: 0.5)
                  : c.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A note being dragged from the Mac notes list onto a folder, project or
/// tag in the sidebar.
class DraggedNote {
  const DraggedNote(this.id, this.title);
  final String id;
  final String title;
}

/// Sidebar sections the reader has folded away (Notes, Projects, Tags).
/// Per session.
final macSidebarCollapsedProvider = StateProvider<Set<String>>((ref) => {});

bool _sameFilter(NotesFilter a, NotesFilter b) => switch ((a, b)) {
  (AllNotes(), AllNotes()) => true,
  (FolderFilter(:final folderId), FolderFilter(folderId: final other)) =>
    folderId == other,
  (TagFilter(:final tagId), TagFilter(tagId: final other)) => tagId == other,
  (ProjectFilter(:final projectId), ProjectFilter(projectId: final other)) =>
    projectId == other,
  _ => false,
};

/// The list column's title for the Notes space: the folder, project or tag
/// being shown, as in Apple Notes.
String notesFilterTitle(
  NotesFilter filter, {
  required List<Folder> folders,
  required List<Project> projects,
  required List<Tag> tags,
}) => switch (filter) {
  AllNotes() => 'Notes',
  FolderFilter(:final folderId) =>
    folders.where((f) => f.id == folderId).firstOrNull?.name ?? 'Notes',
  ProjectFilter(:final projectId) =>
    projects.where((p) => p.id == projectId).firstOrNull?.name ?? 'Notes',
  TagFilter(:final tagId) => switch (tags.where((t) => t.id == tagId)) {
    final found when found.isNotEmpty => '#${found.first.name}',
    _ => 'Notes',
  },
};

/// The Mac source list, laid out like Apple Notes: the space's main
/// action, Library / Search / Attachments, then the Notes section (All
/// Notes and every folder, with counts), Projects and Tags (each only once
/// one exists, each foldable), New Folder, Trash and Settings. Choosing a
/// folder, project or tag shows those notes in the list column; dragging a
/// note onto one files it there. Its tinted background runs up behind the
/// traffic lights; the band they sit in stays empty.
class MacSidebar extends ConsumerWidget {
  const MacSidebar({
    super.key,
    required this.index,
    required this.onSelected,
    required this.onPrimary,
    required this.onSearch,
    required this.onTrash,
    required this.onSettings,
    required this.email,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final VoidCallback onPrimary;
  final VoidCallback onSearch;
  final VoidCallback onTrash;
  final VoidCallback onSettings;
  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final db = ref.read(databaseProvider);
    final projects = ref.watch(projectsListProvider).value ?? const <Project>[];
    final folders = ref.watch(foldersListProvider).value ?? const <Folder>[];
    final tags = ref.watch(tagsListProvider).value ?? const <Tag>[];
    final folderCounts =
        ref.watch(folderNoteCountsProvider).value ?? const <String?, int>{};
    final projectCounts =
        ref.watch(projectNoteCountsProvider).value ?? const <String, int>{};
    final filter = ref.watch(notesFilterProvider);
    final collapsed = ref.watch(macSidebarCollapsedProvider);
    final total = folderCounts.values.fold(0, (a, b) => a + b);

    void show(NotesFilter f) {
      ref.read(notesFilterProvider.notifier).state = f;
      onSelected(0);
    }

    bool shown(NotesFilter f) => index == 0 && _sameFilter(filter, f);

    Widget section(String title) {
      final folded = collapsed.contains(title);
      return _SectionHeader(
        title: title,
        folded: folded,
        onToggle: () => ref.read(macSidebarCollapsedProvider.notifier).state =
            folded ? ({...collapsed}..remove(title)) : {...collapsed, title},
      );
    }

    final (primaryIcon, primaryLabel) = index == 0
        ? (Icons.add, 'New note')
        : (Icons.upload_file_outlined, 'Import PDF');
    return Container(
      key: const ValueKey('mac-sidebar'),
      width: macSidebarWidth,
      color: c.surfaceContainerLow,
      padding: EdgeInsets.fromLTRB(10, top + 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            key: const ValueKey('mac-primary-action'),
            onPressed: onPrimary,
            icon: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.short),
              child: Icon(primaryIcon, key: ValueKey(primaryIcon), size: 18),
            ),
            label: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.short),
              child: Text(primaryLabel, key: ValueKey(primaryLabel)),
            ),
            style: FilledButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size.fromHeight(34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
          const SizedBox(height: 14),
          _SidebarRow(
            icon: Icons.library_books_outlined,
            selectedIcon: Icons.library_books,
            label: 'Library',
            selected: index == 1,
            onTap: () => onSelected(1),
          ),
          _SidebarRow(
            icon: Icons.search,
            label: 'Search',
            selected: false,
            onTap: onSearch,
          ),
          _SidebarRow(
            icon: Icons.attach_file,
            label: 'Attachments',
            selected: false,
            onTap: () => showAttachmentsBrowser(context),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('mac-source-list'),
              padding: EdgeInsets.zero,
              children: [
                section('Notes'),
                if (!collapsed.contains('Notes')) ...[
                  _SidebarRow(
                    key: const ValueKey('mac-all-notes'),
                    icon: Icons.edit_note_outlined,
                    selectedIcon: Icons.edit_note,
                    label: 'All Notes',
                    count: total,
                    selected: shown(const AllNotes()),
                    onTap: () => show(const AllNotes()),
                    onDrop: (note) =>
                        setNoteFolder(db, noteId: note.id, folderId: null),
                  ),
                  for (final f in folders)
                    _SidebarRow(
                      key: ValueKey('mac-folder-${f.id}'),
                      icon: Icons.folder_outlined,
                      selectedIcon: Icons.folder,
                      label: f.name,
                      count: folderCounts[f.id] ?? 0,
                      selected: shown(FolderFilter(f.id)),
                      onTap: () => show(FolderFilter(f.id)),
                      onDrop: (note) =>
                          setNoteFolder(db, noteId: note.id, folderId: f.id),
                      contextActions: [
                        ContextMenuAction(
                          label: 'Rename Folder…',
                          icon: Icons.edit_outlined,
                          onSelected: () async {
                            final name = await _askName(
                              context,
                              title: 'Rename folder',
                              initial: f.name,
                              action: 'Rename',
                            );
                            if (name != null) {
                              await renameFolder(db, f.id, name);
                            }
                          },
                        ),
                        ContextMenuAction(
                          label: 'Delete Folder…',
                          icon: Icons.delete_outline,
                          destructive: true,
                          onSelected: () =>
                              confirmDeleteFolder(context, ref, f),
                        ),
                      ],
                    ),
                ],
                if (projects.isNotEmpty) ...[
                  section('Projects'),
                  if (!collapsed.contains('Projects'))
                    for (final p in projects)
                      _SidebarRow(
                        key: ValueKey('mac-project-${p.id}'),
                        icon: Icons.folder_special_outlined,
                        selectedIcon: Icons.folder_special,
                        label: p.name,
                        count: projectCounts[p.id] ?? 0,
                        selected: shown(ProjectFilter(p.id)),
                        onTap: () => show(ProjectFilter(p.id)),
                        onDrop: (note) => addNoteToProject(
                          db,
                          noteId: note.id,
                          projectId: p.id,
                        ),
                        contextActions: [
                          ContextMenuAction(
                            label: 'Open Project Page',
                            icon: Icons.open_in_new,
                            onSelected: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ProjectScreen(projectId: p.id),
                              ),
                            ),
                          ),
                          ContextMenuAction(
                            label: 'More…',
                            icon: Icons.more_horiz,
                            onSelected: () => showProjectMenu(context, ref, p),
                          ),
                        ],
                      ),
                ],
                if (tags.isNotEmpty) ...[
                  section('Tags'),
                  if (!collapsed.contains('Tags'))
                    for (final t in tags)
                      _SidebarRow(
                        key: ValueKey('mac-tag-${t.id}'),
                        icon: Icons.tag,
                        label: t.name,
                        selected: shown(TagFilter(t.id)),
                        onTap: () => show(TagFilter(t.id)),
                        onDrop: (note) =>
                            addTagToNote(db, noteId: note.id, tagId: t.id),
                        contextActions: [
                          ContextMenuAction(
                            label: 'Delete Tag…',
                            icon: Icons.delete_outline,
                            destructive: true,
                            onSelected: () => confirmDeleteTag(context, ref, t),
                          ),
                        ],
                      ),
                ],
              ],
            ),
          ),
          _SidebarRow(
            key: const ValueKey('mac-new-folder'),
            icon: Icons.create_new_folder_outlined,
            label: 'New Folder',
            selected: false,
            onTap: () async {
              final name = await _askName(
                context,
                title: 'New folder',
                action: 'Create',
              );
              if (name == null) return;
              final id = await createFolder(db, name);
              show(FolderFilter(id));
            },
          ),
          _SidebarRow(
            icon: Icons.delete_outline,
            label: 'Trash',
            selected: false,
            onTap: onTrash,
          ),
          _SidebarRow(
            key: const ValueKey('mac-settings'),
            leading: SyncRing(
              size: 28,
              child: email == null
                  ? const Icon(Icons.account_circle_outlined, size: 20)
                  : CircleAvatar(
                      radius: 10,
                      backgroundColor: c.primaryContainer,
                      foregroundColor: c.onPrimaryContainer,
                      child: Text(
                        email!.isEmpty ? '?' : email![0].toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: c.onPrimaryContainer),
                      ),
                    ),
            ),
            label: email ?? 'Settings',
            selected: false,
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

/// Asks for a folder name; null if cancelled or blank.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, action: action, initial: initial),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Owns its text controller, so it outlives the dialog's closing animation.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(hintText: 'Folder name'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}

/// A source-list section title (Notes, Projects, Tags) with a disclosure
/// chevron that folds the section, as in Apple Notes.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.folded,
    required this.onToggle,
  });

  final String title;
  final bool folded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      button: true,
      label: '$title, ${folded ? 'collapsed' : 'expanded'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: c.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: folded ? -0.25 : 0,
                duration: AppMotion.of(context, AppMotion.short),
                child: Icon(
                  Icons.expand_more,
                  size: 16,
                  color: c.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One compact (32 pt) source-list row.
class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    super.key,
    this.icon,
    this.selectedIcon,
    this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.onDrop,
    this.contextActions = const [],
  });

  final IconData? icon;
  final IconData? selectedIcon;
  final Widget? leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Shown greyed at the right, like Notes' folder counts.
  final int? count;

  /// Accepts a note dragged from the list (files it here).
  final void Function(DraggedNote note)? onDrop;

  /// The right-click menu.
  final List<ContextMenuAction?> contextActions;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;
  bool _focused = false; // keyboard focus ring (keyboard highlight mode only)
  bool _dropping = false; // a note is being dragged over this row

  @override
  Widget build(BuildContext context) {
    final onDrop = widget.onDrop;
    final row = ContextMenuRegion(
      actions: widget.contextActions,
      child: _row(context),
    );
    if (onDrop == null) return row;
    return DragTarget<DraggedNote>(
      onWillAcceptWithDetails: (_) {
        setState(() => _dropping = true);
        return true;
      },
      onLeave: (_) => setState(() => _dropping = false),
      onAcceptWithDetails: (d) {
        setState(() => _dropping = false);
        onDrop(d.data);
      },
      builder: (context, _, _) => row,
    );
  }

  Widget _row(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fg = widget.selected ? c.onPrimaryContainer : c.onSurface;
    final fill = widget.selected
        ? c.primaryContainer
        : _dropping
        ? c.primary.withValues(alpha: 0.16)
        : _hovered
        ? c.onSurface.withValues(alpha: 0.06)
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.short),
            height: 32,
            margin: const EdgeInsets.only(bottom: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _focused ? c.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(
                    child:
                        widget.leading ??
                        Icon(
                          widget.selected
                              ? widget.selectedIcon ?? widget.icon
                              : widget.icon,
                          size: 19,
                          color: widget.selected ? fg : c.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.count case final n?)
                  Text(
                    '$n',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: widget.selected ? fg : c.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
