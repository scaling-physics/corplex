import 'package:flutter/material.dart';

/// One row of a [ContextMenuRegion]'s menu.
class ContextMenuAction {
  const ContextMenuAction({
    required this.label,
    required this.onSelected,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onSelected;

  /// Shown in the error tone (Move to trash).
  final bool destructive;
}

/// A right-click (or Control-click) menu for [child], at the pointer — the
/// desktop counterpart of a long-press. With no [actions] it's just
/// [child]. A null entry in [actions] draws a divider.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<ContextMenuAction?> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (d) =>
          showContextMenuAt(context, d.globalPosition, actions),
      child: child,
    );
  }
}

/// Shows [actions] as a compact popup menu at [position] (global).
Future<void> showContextMenuAt(
  BuildContext context,
  Offset position,
  List<ContextMenuAction?> actions,
) async {
  final c = Theme.of(context).colorScheme;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(position);
  final chosen = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      local & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final (i, a) in actions.indexed)
        if (a == null)
          const PopupMenuDivider(height: 9)
        else
          PopupMenuItem<int>(
            value: i,
            height: 32,
            child: Row(
              children: [
                if (a.icon != null) ...[
                  Icon(
                    a.icon,
                    size: 18,
                    color: a.destructive ? c.error : c.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  a.label,
                  style: a.destructive ? TextStyle(color: c.error) : null,
                ),
              ],
            ),
          ),
    ],
  );
  if (chosen != null) actions[chosen]!.onSelected();
}
