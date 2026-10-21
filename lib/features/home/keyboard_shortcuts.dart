import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// One shortcut: what it does and its key caps (⌘ ⇧ ⌥ ⌃ then the key).
class ShortcutEntry {
  const ShortcutEntry(this.label, this.keys);
  final String label;
  final List<String> keys;
}

/// The Mac menu bar's shortcuts (`MainFlutterWindow.swift`) plus the
/// keyboard navigation that needs no menu.
List<(String, List<ShortcutEntry>)> shortcutSections(AppLocalizations l) => [
  (
    l.macShortcutsGeneral,
    [
      ShortcutEntry(l.macKeyNewNote, ['⌘', 'N']),
      ShortcutEntry(l.dailyKeyTodaysNote, ['⌘', 'T']),
      ShortcutEntry(l.macKeyImportPdf, ['⌘', 'O']),
      ShortcutEntry(l.macKeyQuickNote, ['⌃', '⌥', 'N']),
      ShortcutEntry(l.macKeyDuplicateNote, ['⌘', 'D']),
      ShortcutEntry(l.macKeyPrint, ['⌘', 'P']),
      ShortcutEntry(l.macKeyMoveToTrash, ['⌘', '⌫']),
      ShortcutEntry(l.macKeySettings, ['⌘', ',']),
      ShortcutEntry(l.macKeyShortcuts, ['⌘', '/']),
      ShortcutEntry(l.macKeyLargerInterface, ['⌥', '⌘', '+']),
      ShortcutEntry(l.macKeySmallerInterface, ['⌥', '⌘', '−']),
      ShortcutEntry(l.macKeyDefaultInterface, ['⌥', '⌘', '0']),
      ShortcutEntry(l.panesClose, ['⌘', 'W']),
      ShortcutEntry(l.macKeyCloseWindow, ['⇧', '⌘', 'W']),
    ],
  ),
  (
    l.macShortcutsFormatting,
    [
      ShortcutEntry(l.macKeyBold, ['⌘', 'B']),
      ShortcutEntry(l.macKeyItalic, ['⌘', 'I']),
      ShortcutEntry(l.macKeyUnderline, ['⌘', 'U']),
      ShortcutEntry(l.macKeyStrikethrough, ['⇧', '⌘', 'X']),
      ShortcutEntry(l.macKeyHighlight, ['⇧', '⌘', 'E']),
      ShortcutEntry(l.macKeyMonospaced, ['⇧', '⌘', 'M']),
      ShortcutEntry(l.macKeyTitle, ['⇧', '⌘', 'T']),
      ShortcutEntry(l.macKeyHeading, ['⇧', '⌘', 'H']),
      ShortcutEntry(l.macKeySubheading, ['⇧', '⌘', 'J']),
      ShortcutEntry(l.macKeyBody, ['⇧', '⌘', 'B']),
      ShortcutEntry(l.macKeyBulletedList, ['⇧', '⌘', '7']),
      ShortcutEntry(l.macKeyNumberedList, ['⇧', '⌘', '9']),
      ShortcutEntry(l.macKeyChecklist, ['⇧', '⌘', 'L']),
      ShortcutEntry(l.macKeyBlockQuote, ['⌘', '\'']),
      ShortcutEntry(l.macKeyTable, ['⌥', '⌘', 'T']),
      ShortcutEntry(l.macKeyAddComment, ['⌥', '⌘', 'K']),
      ShortcutEntry(l.macKeyLinkNote, ['⌘', 'K']),
      ShortcutEntry(l.macKeyCitePaper, ['⇧', '⌘', 'K']),
      ShortcutEntry(l.footnotesCommand, ['⌥', '⌘', 'F']),
      ShortcutEntry(l.switcherKeyOpenLink, ['⌘', 'L']),
      ShortcutEntry(l.blocksKeyMoveUp, ['⌃', '⌘', '↑']),
      ShortcutEntry(l.blocksKeyMoveDown, ['⌃', '⌘', '↓']),
    ],
  ),
  (
    l.macShortcutsReader,
    [
      ShortcutEntry(l.macKeyFindInDocument, ['⌘', 'F']),
      ShortcutEntry(l.macKeyFindNext, ['⌘', 'G']),
      ShortcutEntry(l.macKeyFindPrevious, ['⇧', '⌘', 'G']),
      ShortcutEntry(l.macKeyZoomIn, ['⌘', '+']),
      ShortcutEntry(l.macKeyZoomOut, ['⌘', '−']),
      ShortcutEntry(l.macKeyActualSize, ['⌘', '0']),
    ],
  ),
  (
    l.macShortcutsNavigation,
    [
      ShortcutEntry(l.macKeyNotes, ['⌘', '1']),
      ShortcutEntry(l.macKeyLibrary, ['⌘', '2']),
      ShortcutEntry(l.macKeyAttachments, ['⌘', '3']),
      ShortcutEntry(l.macKeySearch, ['⇧', '⌘', 'F']),
      ShortcutEntry(l.switcherKeyGoTo, ['⌘', 'K']),
      ShortcutEntry(l.switcherKeyGoTo, ['⇧', '⌘', 'O']),
      ShortcutEntry(l.switcherKeyPrevHeading, ['⌥', '⌘', '↑']),
      ShortcutEntry(l.switcherKeyNextHeading, ['⌥', '⌘', '↓']),
      ShortcutEntry(l.macKeySidebar, ['⌃', '⌘', 'S']),
      ShortcutEntry(l.outlineKeyOutline, ['⌃', '⌘', 'O']),
      ShortcutEntry(l.macKeyBack, ['⌘', '[']),
      ShortcutEntry(l.historyKeyForward, ['⌘', ']']),
      ShortcutEntry(l.macKeyMoveThroughList, ['↑', '↓']),
      ShortcutEntry(l.macKeyOpenSelected, ['Return']),
      ShortcutEntry(l.macKeyNextColumn, ['Tab']),
      ShortcutEntry(l.macKeyCloseDialog, ['Esc']),
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
              context.l10n.macShortcutsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (title, entries) in shortcutSections(
                    context.l10n,
                  )) ...[
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
