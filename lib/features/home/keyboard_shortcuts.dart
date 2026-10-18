import 'package:flutter/material.dart';

/// One shortcut: what it does and its key caps (⌘ ⇧ ⌥ ⌃ then the key).
class ShortcutEntry {
  const ShortcutEntry(this.label, this.keys);
  final String label;
  final List<String> keys;
}

/// The Mac menu bar's shortcuts (`MainFlutterWindow.swift`) plus the
/// keyboard navigation that needs no menu.
const shortcutSections = <(String, List<ShortcutEntry>)>[
  (
    'General',
    [
      ShortcutEntry('New note', ['⌘', 'N']),
      ShortcutEntry('Import PDF', ['⌘', 'O']),
      ShortcutEntry('Quick note from anywhere', ['⌃', '⌥', 'N']),
      ShortcutEntry('Duplicate note', ['⌘', 'D']),
      ShortcutEntry('Print', ['⌘', 'P']),
      ShortcutEntry('Move to Trash', ['⌘', '⌫']),
      ShortcutEntry('Settings', ['⌘', ',']),
      ShortcutEntry('Keyboard shortcuts', ['⌘', '/']),
      ShortcutEntry('Larger interface', ['⌥', '⌘', '+']),
      ShortcutEntry('Smaller interface', ['⌥', '⌘', '−']),
      ShortcutEntry('Default interface size', ['⌥', '⌘', '0']),
      ShortcutEntry('Close window', ['⌘', 'W']),
    ],
  ),
  (
    'Notes & Formatting',
    [
      ShortcutEntry('Bold', ['⌘', 'B']),
      ShortcutEntry('Italic', ['⌘', 'I']),
      ShortcutEntry('Underline', ['⌘', 'U']),
      ShortcutEntry('Strikethrough', ['⇧', '⌘', 'X']),
      ShortcutEntry('Highlight', ['⇧', '⌘', 'E']),
      ShortcutEntry('Monospaced', ['⇧', '⌘', 'M']),
      ShortcutEntry('Title', ['⇧', '⌘', 'T']),
      ShortcutEntry('Heading', ['⇧', '⌘', 'H']),
      ShortcutEntry('Subheading', ['⇧', '⌘', 'J']),
      ShortcutEntry('Body', ['⇧', '⌘', 'B']),
      ShortcutEntry('Bulleted list', ['⇧', '⌘', '7']),
      ShortcutEntry('Numbered list', ['⇧', '⌘', '9']),
      ShortcutEntry('Checklist', ['⇧', '⌘', 'L']),
      ShortcutEntry('Block quote', ['⌘', '\'']),
      ShortcutEntry('Table', ['⌥', '⌘', 'T']),
      ShortcutEntry('Add comment', ['⌥', '⌘', 'K']),
      ShortcutEntry('Link to a note', ['⌘', 'K']),
      ShortcutEntry('Cite a paper', ['⇧', '⌘', 'K']),
    ],
  ),
  (
    'Library & Reader',
    [
      ShortcutEntry('Find in document', ['⌘', 'F']),
      ShortcutEntry('Find next', ['⌘', 'G']),
      ShortcutEntry('Find previous', ['⇧', '⌘', 'G']),
      ShortcutEntry('Zoom in', ['⌘', '+']),
      ShortcutEntry('Zoom out', ['⌘', '−']),
      ShortcutEntry('Actual size', ['⌘', '0']),
    ],
  ),
  (
    'Navigation',
    [
      ShortcutEntry('Notes', ['⌘', '1']),
      ShortcutEntry('Library', ['⌘', '2']),
      ShortcutEntry('Attachments', ['⌘', '3']),
      ShortcutEntry('Search', ['⇧', '⌘', 'F']),
      ShortcutEntry('Show or hide the sidebar', ['⌃', '⌘', 'S']),
      ShortcutEntry('Back', ['⌘', '[']),
      ShortcutEntry('Move through a list', ['↑', '↓']),
      ShortcutEntry('Open the selected item', ['Return']),
      ShortcutEntry('Next or previous column', ['Tab']),
      ShortcutEntry('Close a dialog or menu', ['Esc']),
    ],
  ),
];

/// Help > Keyboard Shortcuts: a centred, scrollable dialog.
Future<void> showKeyboardShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    key: const ValueKey('keyboard-shortcuts'),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(
              'Keyboard Shortcuts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (title, entries) in shortcutSections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 6),
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    for (final e in entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.label,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            for (final k in e.keys) KeyCap(k),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

/// A key drawn as a small rounded box.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceContainerHigh,
        border: Border.all(color: c.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: c.onSurface, fontWeight: FontWeight.w500),
      ),
    );
  }
}
