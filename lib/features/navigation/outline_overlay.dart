import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../notes/note_sections.dart' show NoteHeading;

/// The index of the heading the caret is under: the last heading at or
/// before [caret] (offsets in the whole, unfolded note), or -1 before the
/// first.
int currentHeadingIndex(List<NoteHeading> headings, int caret) {
  var at = -1;
  for (var i = 0; i < headings.length; i++) {
    if (headings[i].offset <= caret) at = i;
  }
  return at;
}

/// A note zoomed out to its headings: levels indented, the current section
/// marked. Tap or Return jumps there; Escape, a tap outside or [onClose]
/// (pinch-in) closes. Nothing shows until it's opened.
class OutlineOverlay extends StatefulWidget {
  const OutlineOverlay({
    super.key,
    required this.headings,
    required this.current,
    required this.onPick,
    required this.onClose,
  });

  final List<NoteHeading> headings;
  final int current;
  final ValueChanged<NoteHeading> onPick;
  final VoidCallback onClose;

  @override
  State<OutlineOverlay> createState() => _OutlineOverlayState();
}

class _OutlineOverlayState extends State<OutlineOverlay> {
  late int _selected = widget.current < 0 ? 0 : widget.current;

  void _move(int delta) {
    if (widget.headings.isEmpty) return;
    setState(
      () =>
          _selected = (_selected + delta).clamp(0, widget.headings.length - 1),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (widget.headings.isNotEmpty) {
        widget.onPick(widget.headings[_selected]);
      } else {
        widget.onClose();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.short),
      curve: AppMotion.standard,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('outline-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: ColoredBox(color: c.scrim.withValues(alpha: 0.18)),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 560,
                ),
                child: Material(
                  key: const ValueKey('outline-panel'),
                  color: c.surface,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          context.l10n.outlineTitle,
                          style: text.titleMedium,
                        ),
                      ),
                      if (widget.headings.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: Text(
                            context.l10n.outlineEmpty,
                            style: text.bodyMedium?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 10),
                            itemCount: widget.headings.length,
                            itemBuilder: (context, i) {
                              final h = widget.headings[i];
                              final here = i == widget.current;
                              return InkWell(
                                key: ValueKey('outline-$i'),
                                onTap: () => widget.onPick(h),
                                child: Container(
                                  color: i == _selected
                                      ? c.primaryContainer.withValues(
                                          alpha: 0.5,
                                        )
                                      : null,
                                  padding: EdgeInsets.fromLTRB(
                                    20 + (h.level - 1) * 18.0,
                                    7,
                                    20,
                                    7,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          h.text,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              (h.level == 1
                                                      ? text.titleSmall
                                                      : text.bodyMedium)
                                                  ?.copyWith(
                                                    fontWeight: here
                                                        ? FontWeight.w700
                                                        : null,
                                                    color: here
                                                        ? c.primary
                                                        : null,
                                                  ),
                                        ),
                                      ),
                                      if (here)
                                        Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: c.primary,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
