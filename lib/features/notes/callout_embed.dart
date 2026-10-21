import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';
import '../platform/mac_window.dart' show isDesktop;
import 'callout_markers.dart';

/// The icon of a callout [type]; any unknown word is drawn as a note.
IconData calloutIcon(String type) => switch (type.toLowerCase()) {
  'info' => Icons.info_outline,
  'tip' => Icons.lightbulb_outline,
  'success' => Icons.check_circle_outline,
  'example' => Icons.format_list_bulleted,
  'important' => Icons.priority_high,
  'question' => Icons.help_outline,
  'todo' => Icons.check_box_outlined,
  'warning' => Icons.warning_amber_outlined,
  'caution' => Icons.report_problem_outlined,
  'danger' => Icons.dangerous_outlined,
  'bug' => Icons.bug_report_outlined,
  _ => Icons.edit_note,
};

/// The name shown for a callout [type] in the app's language; a word of the
/// reader's own is shown as written, capitalised.
String calloutTypeName(AppLocalizations l10n, String type) =>
    switch (type.toLowerCase()) {
      'note' => l10n.calloutsTypeNote,
      'info' => l10n.calloutsTypeInfo,
      'tip' => l10n.calloutsTypeTip,
      'success' => l10n.calloutsTypeSuccess,
      'example' => l10n.calloutsTypeExample,
      'important' => l10n.calloutsTypeImportant,
      'question' => l10n.calloutsTypeQuestion,
      'todo' => l10n.calloutsTypeTodo,
      'warning' => l10n.calloutsTypeWarning,
      'caution' => l10n.calloutsTypeCaution,
      'danger' => l10n.calloutsTypeDanger,
      'bug' => l10n.calloutsTypeBug,
      _ => calloutLabel(type),
    };

/// Background and foreground of a tone, from the theme only.
(Color, Color) calloutColors(ColorScheme c, CalloutTone tone) => switch (tone) {
  CalloutTone.primary => (c.primaryContainer, c.onPrimaryContainer),
  CalloutTone.tertiary => (c.tertiaryContainer, c.onTertiaryContainer),
  CalloutTone.secondary => (c.secondaryContainer, c.onSecondaryContainer),
  CalloutTone.error => (c.errorContainer, c.onErrorContainer),
};

/// The chip at the start of a callout's first line: icon and label. Tap to
/// change the type or remove the callout.
class CalloutEmbedBuilder extends EmbedBuilder {
  const CalloutEmbedBuilder();

  @override
  String get key => calloutEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => node.value.data as String;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final marker = embedContext.node.value.data as String;
    final type = parseCalloutLine(marker)?.type ?? 'note';
    final (bg, fg) = calloutColors(
      Theme.of(context).colorScheme,
      calloutToneOf(type),
    );
    final name = calloutTypeName(context.l10n, type);
    final style = embedContext.textStyle;
    return Semantics(
      button: !embedContext.readOnly,
      label: context.l10n.calloutsLabel(name),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: embedContext.readOnly
            ? null
            : () => editCalloutAt(
                context,
                embedContext.controller,
                embedContext.node.documentOffset,
              ),
        child: Container(
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                calloutIcon(type),
                size: (style.fontSize ?? 16) * 1.05,
                color: fg,
              ),
              const SizedBox(width: 4),
              Text(
                name,
                style: style.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the picker returns for "Remove callout".
const calloutRemoveChoice = '';

/// Asks for a callout type. Returns the type, [calloutRemoveChoice] to remove
/// the callout (only offered when [canRemove]), or null when dismissed.
Future<String?> showCalloutPicker(
  BuildContext context, {
  String? current,
  bool canRemove = false,
}) {
  Widget list(BuildContext context) {
    final l10n = context.l10n;
    final c = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.calloutsPickTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          for (final type in calloutPickerTypes)
            ListTile(
              key: ValueKey('callout-$type'),
              dense: isDesktop(context),
              leading: Icon(
                calloutIcon(type),
                color: calloutColors(c, calloutToneOf(type)).$2,
              ),
              title: Text(calloutTypeName(l10n, type)),
              selected: type == current,
              onTap: () => Navigator.pop(context, type),
            ),
          if (canRemove)
            ListTile(
              key: const ValueKey('callout-remove'),
              dense: isDesktop(context),
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.calloutsRemove),
              onTap: () => Navigator.pop(context, calloutRemoveChoice),
            ),
        ],
      ),
    );
  }

  if (isDesktop(context)) {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: list(context),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(child: list(context)),
  );
}

Embed? _calloutAt(Document doc, int offset) {
  if (offset < 0 || offset >= doc.length) return null;
  final leaf = doc.querySegmentLeafNode(offset).leaf;
  if (leaf is Embed &&
      leaf.documentOffset == offset &&
      leaf.value.type == calloutEmbedType) {
    return leaf;
  }
  return null;
}

/// Changes or removes the callout whose chip is at [offset].
Future<void> editCalloutAt(
  BuildContext context,
  QuillController controller,
  int offset,
) async {
  final leaf = _calloutAt(controller.document, offset);
  if (leaf == null) return;
  final marker = leaf.value.data as String;
  final choice = await showCalloutPicker(
    context,
    current: parseCalloutLine(marker)?.type,
    canRemove: true,
  );
  if (choice == null) return;
  final now = _calloutAt(controller.document, offset);
  if (now == null) return;
  if (choice == calloutRemoveChoice) {
    // The space after the chip goes with it.
    final text = controller.document.toPlainText();
    final space = offset + 1 < text.length && text[offset + 1] == ' ';
    controller.replaceText(
      offset,
      space ? 2 : 1,
      '',
      TextSelection.collapsed(offset: offset),
    );
    return;
  }
  // Keep Obsidian's fold sign if the marker had one.
  final fold = RegExp(r'\][+-]$').hasMatch(marker)
      ? marker.substring(marker.length - 1)
      : '';
  controller.replaceText(
    offset,
    1,
    Embeddable(calloutEmbedType, '${calloutMarker(choice)}$fold'),
    null,
  );
}

/// The `/` → "Callout" command: asks for a type and makes the current line a
/// quote line that starts with it (the line's text becomes the title). A line
/// that is already a callout just changes type.
Future<void> insertCallout(
  BuildContext context,
  QuillController controller,
) async {
  final doc = controller.document;
  final cursor = controller.selection.extentOffset;
  final index = cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor;
  final line = doc.queryChild(index).node;
  if (line is! Line) return;
  final start = line.documentOffset;
  final existing = _calloutAt(doc, start);
  if (existing != null) {
    await editCalloutAt(context, controller, start);
    return;
  }
  final type = await showCalloutPicker(context);
  if (type == null || type.isEmpty) return;
  // The document may have moved while the picker was open.
  final now = controller.document.queryChild(start).node;
  if (now is! Line || now.documentOffset != start) return;
  final wasEmpty = now.length <= 1;
  final end = start + now.length - 1;
  final quoted = now.style.attributes.containsKey(Attribute.blockQuote.key);
  controller.replaceText(
    start,
    0,
    Embeddable(calloutEmbedType, calloutMarker(type)),
    null,
  );
  controller.replaceText(start + 1, 0, ' ', null);
  controller.updateSelection(
    TextSelection.collapsed(offset: wasEmpty ? start + 2 : end + 2),
    ChangeSource.local,
  );
  if (!quoted) controller.formatSelection(Attribute.blockQuote);
}
