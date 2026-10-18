import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The text highlight colours: soft pastels from the family of the PDF
/// highlighter inks. Stored as Quill's `background` attribute with the hex
/// value, so a highlight is part of the Delta and syncs/merges with it.
enum NoteHighlight {
  yellow('Yellow', '#F5E39A'),
  green('Green', '#BFDDB8'),
  blue('Blue', '#BCD6EA'),
  pink('Pink', '#F0C4C0'),
  purple('Purple', '#D5C6E8');

  const NoteHighlight(this.label, this.hex);

  final String label;
  final String hex;

  Color get color => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  Attribute<String?> get attribute => BackgroundAttribute(hex);
}

/// The ink on a highlight: dark in both schemes, since the pastel is light
/// even when the page is dark.
const highlightInk = Color(0xFF2B2824);

/// `RRGGBB` (upper case, no `#`) for a `background` attribute value, or
/// null when it isn't a plain hex colour.
String? highlightHex(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value.trim());
  return m?.group(1)!.toUpperCase();
}

/// Editor `customStyleBuilder`: dark ink on a highlight.
TextStyle noteStyleFor(Attribute attribute) =>
    attribute.key == Attribute.background.key && attribute.value != null
    ? const TextStyle(color: highlightInk)
    : const TextStyle();

/// The highlight under the selection, if it is a single palette colour.
String? selectionHighlight(QuillController controller) {
  final v = controller.getSelectionStyle().attributes[Attribute.background.key];
  return v?.value as String?;
}

/// Highlights the selection in [color]; the same colour again removes it.
void applyHighlight(QuillController controller, NoteHighlight color) {
  final current = highlightHex(selectionHighlight(controller));
  controller.formatSelection(
    current == color.hex.substring(1)
        ? const BackgroundAttribute(null)
        : color.attribute,
  );
}

void removeHighlight(QuillController controller) =>
    controller.formatSelection(const BackgroundAttribute(null));

/// The popup items for choosing a highlight: five colours and Remove.
/// The value of the "Remove highlight" item.
const removeHighlightChoice = 'remove';

/// Applies a [highlightMenuItems] choice and remembers the colour.
void chooseHighlight(QuillController controller, Object choice) {
  if (choice is NoteHighlight) {
    lastHighlight = choice;
    applyHighlight(controller, choice);
  } else {
    removeHighlight(controller);
  }
}

/// The colour Format → Highlight applies; the last one chosen.
NoteHighlight lastHighlight = NoteHighlight.yellow;

List<PopupMenuEntry<Object>> highlightMenuItems(
  BuildContext context,
  QuillController controller,
) {
  final current = highlightHex(selectionHighlight(controller));
  return [
    for (final h in NoteHighlight.values)
      PopupMenuItem<Object>(
        value: h,
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: h.color,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: current == h.hex.substring(1)
                  ? const Icon(Icons.check, size: 13, color: highlightInk)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(h.label),
          ],
        ),
      ),
    if (current != null) ...[
      const PopupMenuDivider(),
      const PopupMenuItem<Object>(
        value: removeHighlightChoice,
        child: Text('Remove highlight'),
      ),
    ],
  ];
}
