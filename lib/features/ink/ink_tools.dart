import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'ink_model.dart';
import 'pencil_taps.dart';

/// Drawn on light "paper" in both themes, like a real sheet, so ink colors
/// read the same everywhere a sketch is shown.
const sketchPaperColor = Color(0xFFFBFAF6);

const penInks = [
  Color(0xFF2B2F2B), // graphite
  Color(0xFF55715A), // sage
  Color(0xFFA0664F), // clay
  Color(0xFF3F5F8A), // ink blue
];

const highlighterInks = [
  Color(0xFFF2D66B), // butter
  Color(0xFF9CC79A), // sage
  Color(0xFFEBA9A4), // rose
  Color(0xFF9DC3DE), // mist blue
];

const penWidths = [0.004, 0.007, 0.012];
const highlighterWidth = 0.03;

enum InkToolKind { pen, highlighter, eraser }

/// The chosen tool, inks and thickness, shared by the inline drawings in a
/// note and the full-screen sketch editor. Follows Apple Pencil double-tap
/// (the iPadOS preference) through [applyPencilTap].
class InkTools extends ChangeNotifier {
  InkToolKind _tool = InkToolKind.pen;
  InkToolKind _previousTool = InkToolKind.eraser;
  int _penInk = 0;
  int _highlighterInk = 0;
  int _penWidth = 1;

  InkToolKind get tool => _tool;
  int get penInk => _penInk;
  int get highlighterInk => _highlighterInk;
  int get penWidth => _penWidth;

  bool get erasing => _tool == InkToolKind.eraser;
  InkTool get inkTool =>
      _tool == InkToolKind.highlighter ? InkTool.highlighter : InkTool.pen;
  Color get color => _tool == InkToolKind.highlighter
      ? highlighterInks[_highlighterInk]
      : penInks[_penInk];
  double get width => _tool == InkToolKind.highlighter
      ? highlighterWidth
      : penWidths[_penWidth];

  void setTool(InkToolKind tool) {
    if (tool == _tool) return;
    _previousTool = _tool;
    _tool = tool;
    notifyListeners();
  }

  /// Picks ink [i] of the current tool's row (switching the eraser to pen).
  void setInk(int i) {
    if (_tool == InkToolKind.highlighter) {
      _highlighterInk = i;
    } else {
      _penInk = i;
      if (_tool == InkToolKind.eraser) setTool(InkToolKind.pen);
    }
    notifyListeners();
  }

  void setPenWidth(int i) {
    _penWidth = i;
    if (_tool != InkToolKind.pen) {
      setTool(InkToolKind.pen);
    } else {
      notifyListeners();
    }
  }

  /// Double-tap on the Pencil, as configured in iPadOS Settings.
  void applyPencilTap(PencilAction action) {
    switch (action) {
      case PencilAction.switchEraser:
        setTool(
          _tool == InkToolKind.eraser ? _previousTool : InkToolKind.eraser,
        );
      case PencilAction.switchPrevious:
        setTool(_previousTool);
      case PencilAction.showColorPalette:
        // There's one row of inks; the tap steps to the next one.
        if (_tool == InkToolKind.highlighter) {
          _highlighterInk = (_highlighterInk + 1) % highlighterInks.length;
        } else if (_tool == InkToolKind.pen) {
          _penInk = (_penInk + 1) % penInks.length;
        }
        notifyListeners();
      case PencilAction.ignore:
        break;
    }
  }
}

/// The floating tool palette: pen / highlighter / eraser, inks, and (for
/// the pen) three thicknesses, then any [trailing] actions (undo, done…).
class InkPalette extends StatelessWidget {
  const InkPalette({
    super.key,
    required this.tools,
    this.trailing = const [],
    this.end,
  });

  final InkTools tools;
  final List<Widget> trailing;

  /// Kept in view at the end (Done): on a narrow phone the rest scrolls
  /// sideways, this doesn't.
  final Widget? end;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final tool = tools.tool;
    final inks = tool == InkToolKind.highlighter ? highlighterInks : penInks;
    final ink = tool == InkToolKind.highlighter
        ? tools.highlighterInk
        : tools.penInk;

    Widget toolButton(InkToolKind t, IconData icon, String label) => IconButton(
      isSelected: tool == t,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: tool == t ? c.primaryContainer : null,
        foregroundColor: tool == t ? c.onPrimaryContainer : c.onSurfaceVariant,
      ),
      icon: Icon(icon),
      tooltip: label,
      onPressed: () => tools.setTool(t),
    );

    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(width: 1, height: 28, color: c.outlineVariant),
    );

    return Material(
      color: c.surfaceContainerLowest,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    toolButton(InkToolKind.pen, Icons.edit_outlined, 'Pen'),
                    toolButton(
                      InkToolKind.highlighter,
                      Icons.border_color_outlined,
                      'Highlighter',
                    ),
                    toolButton(
                      InkToolKind.eraser,
                      Icons.cleaning_services_outlined,
                      'Eraser',
                    ),
                    AnimatedSize(
                      duration: AppMotion.medium,
                      curve: AppMotion.standard,
                      child: tool == InkToolKind.eraser
                          ? const SizedBox.shrink()
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                divider(),
                                for (var i = 0; i < inks.length; i++)
                                  _Swatch(
                                    color: inks[i],
                                    selected: i == ink,
                                    onTap: () => tools.setInk(i),
                                  ),
                                if (tool == InkToolKind.pen) ...[
                                  divider(),
                                  for (var i = 0; i < penWidths.length; i++)
                                    _WidthDot(
                                      size: 6.0 + i * 5,
                                      selected: i == tools.penWidth,
                                      onTap: () => tools.setPenWidth(i),
                                    ),
                                ],
                              ],
                            ),
                    ),
                    if (trailing.isNotEmpty) ...[divider(), ...trailing],
                  ],
                ),
              ),
            ),
            if (end case final end?) ...[const SizedBox(width: 4), end],
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Ink color',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.short,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? c.primary : c.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  const _WidthDot({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Line thickness',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.primaryContainer : null,
            shape: BoxShape.circle,
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected ? c.onPrimaryContainer : c.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
