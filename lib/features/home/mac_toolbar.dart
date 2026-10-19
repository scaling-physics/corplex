import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../platform/mac_window.dart';

/// The Mac window's toolbar row, laid out like Notes: one [macToolbarHeight]
/// band across the top of the window, level with the traffic lights. Each
/// column draws its own part of the row — the sidebar (New Folder, hide the
/// sidebar), the list (its title, count and ⋯ menu) and the pane (New note,
/// the note's formatting and actions, then the search field at the far
/// right). Empty space in the row drags the window ([MacWindowDragArea]).

/// What the pane's screen puts at the ends of its own toolbar row: the
/// shell's New note / Import PDF button first, its search field last. A
/// note or paper shown in the pane reads it and sets its app bar to the
/// row's height (`MacPaneChrome.maybeOf`); anywhere else there is none and
/// the screen keeps its usual app bar.
class MacPaneChrome extends InheritedWidget {
  const MacPaneChrome({
    super.key,
    required this.leading,
    required this.trailing,
    required super.child,
  });

  /// The space's primary action (New note, Import PDF).
  final Widget leading;

  /// The search field.
  final Widget trailing;

  /// Room for [leading] in an app bar.
  static const leadingWidth = 52.0;

  static MacPaneChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MacPaneChrome>();

  @override
  bool updateShouldNotify(MacPaneChrome old) =>
      leading != old.leading || trailing != old.trailing;
}

/// A toolbar button as in Notes' row: an icon in a soft round well.
class MacToolbarButton extends StatelessWidget {
  const MacToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 19),
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(34),
        minimumSize: const Size.square(34),
        padding: EdgeInsets.zero,
        backgroundColor: c.surfaceContainerHighest.withValues(alpha: 0.6),
        foregroundColor: c.onSurfaceVariant,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// The search field at the right end of the toolbar row. Typing searches
/// notes, papers, highlights and papers' text, and the list column shows
/// the results; Escape (or ×) clears it.
class MacToolbarSearch extends StatelessWidget {
  const MacToolbarSearch({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.width = 200,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final double width;

  void _clear() {
    controller.clear();
    onChanged('');
    focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    // Centred: an app bar stretches its actions to the row's height.
    return Center(
      widthFactor: 1,
      child: Padding(
        padding: const EdgeInsets.only(left: 6, right: 12),
        child: SizedBox(
          key: const ValueKey('mac-toolbar-search'),
          width: width,
          height: 30,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _clear,
            },
            child: ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyMedium,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: context.l10n.commonSearch,
                  isDense: true,
                  filled: true,
                  fillColor: c.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 17,
                    color: c.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.cancel, size: 15),
                          tooltip: context.l10n.searchClear,
                          onPressed: _clear,
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 28),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A column's part of the toolbar row: [leadingInset] of free space (the
/// traffic lights, when this column starts at the window's left edge),
/// then [leading] controls, a title with a quiet [subtitle] under it (the
/// list's folder and its count, as in Notes), and [actions] on the right.
/// Empty space drags the window.
class MacToolbarRow extends StatelessWidget {
  const MacToolbarRow({
    super.key,
    this.leadingInset = 0,
    this.leading = const [],
    this.title,
    this.subtitle,
    this.actions = const [],
    this.titleKey,
  });

  final double leadingInset;
  final List<Widget> leading;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: macToolbarHeight,
      child: Stack(
        children: [
          const Positioned.fill(child: MacWindowDragArea()),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(left: leadingInset + 10, right: 10),
              child: Row(
                children: [
                  for (final w in leading) ...[w, const SizedBox(width: 6)],
                  if (title != null)
                    Expanded(
                      child: IgnorePointer(
                        // The title is part of the drag area, as in Notes.
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title!,
                                key: titleKey,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  for (final w in actions) ...[const SizedBox(width: 6), w],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The toolbar row for a pane screen with nothing of its own to put in it
/// (no note chosen, a note still loading): just [chrome]'s two ends.
PreferredSizeWidget macPaneBar(MacPaneChrome chrome) => AppBar(
  toolbarHeight: macToolbarHeight,
  automaticallyImplyLeading: false,
  leading: Center(child: chrome.leading),
  leadingWidth: MacPaneChrome.leadingWidth,
  actions: [chrome.trailing],
  flexibleSpace: const MacWindowDragArea(),
);
