import 'package:flutter/material.dart';

/// A row in a Mac source/content list, in the manner of Apple Notes: no
/// card, a bold title over a quiet second line, a hairline between rows,
/// and a rounded tint when selected (stronger while the list has keyboard
/// focus, as AppKit does). Hover tints faintly. Used on desktop in place of
/// the touch-sized cards.
class MacListRow extends StatefulWidget {
  const MacListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.listFocused = false,
    this.showDivider = true,
    this.onTap,
    this.onDoubleTap,
  });

  final Widget title;

  /// The second line(s): e.g. "Today  First words of the note…".
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;

  /// Whether the list holding this row has keyboard focus: the selection
  /// then shows in the accent colour, otherwise in a neutral grey.
  final bool listFocused;

  /// A hairline under the row (hidden next to a selected row by the caller
  /// if it wants; Notes keeps them).
  final bool showDivider;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<MacListRow> createState() => _MacListRowState();
}

class _MacListRowState extends State<MacListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final selected = widget.selected;
    final Color background = selected
        ? (widget.listFocused ? c.primaryContainer : c.surfaceContainerHigh)
        : _hover
        ? c.onSurface.withValues(alpha: 0.04)
        : Colors.transparent;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      color: selected && widget.listFocused
          ? c.onPrimaryContainer
          : c.onSurface,
      fontWeight: FontWeight.w600,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: selected && widget.listFocused
          ? c.onPrimaryContainer.withValues(alpha: 0.8)
          : c.onSurfaceVariant,
      height: 1.35,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DefaultTextStyle.merge(
                              style: titleStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: widget.title,
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 2),
                              DefaultTextStyle.merge(
                                style: subtitleStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                child: widget.subtitle!,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.trailing != null) ...[
                        const SizedBox(width: 8),
                        widget.trailing!,
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.showDivider)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: c.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
