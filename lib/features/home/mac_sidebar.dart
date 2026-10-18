import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
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

/// The Mac source list: the current space's main action, Notes and
/// Library, Search, projects (only once some exist), and at the bottom
/// Trash and Settings. Its tinted background runs up behind the traffic
/// lights; the band they sit in stays empty.
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
    final projects = ref.watch(projectsListProvider).value ?? const <Project>[];
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
            icon: Icons.edit_note_outlined,
            selectedIcon: Icons.edit_note,
            label: 'Notes',
            selected: index == 0,
            onTap: () => onSelected(0),
          ),
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
          if (projects.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 4),
              child: Text(
                'Projects',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: c.onSurfaceVariant, letterSpacing: 0.4),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final p in projects)
                    _SidebarRow(
                      icon: Icons.folder_open_outlined,
                      label: p.name,
                      selected: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProjectScreen(projectId: p.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ] else
            const Spacer(),
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
  });

  final IconData? icon;
  final IconData? selectedIcon;
  final Widget? leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;
  bool _focused = false; // keyboard focus ring (keyboard highlight mode only)

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fg = widget.selected ? c.onPrimaryContainer : c.onSurface;
    final fill = widget.selected
        ? c.primaryContainer
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
