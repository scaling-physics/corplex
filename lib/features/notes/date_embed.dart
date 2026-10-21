import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';
import '../platform/mac_window.dart' show isDesktop;
import 'date_markers.dart';

/// The clock the chips read (tests replace it).
DateTime Function() dateMentionNow = DateTime.now;

/// Is the paragraph holding [offset] a checked checklist item?
bool _inCheckedItem(Document doc, int offset) {
  if (offset < 0 || offset >= doc.length) return false;
  final node = doc.queryChild(offset).node;
  if (node is Line) {
    return node.style.attributes[Attribute.list.key]?.value ==
        Attribute.checked.value;
  }
  return false;
}

/// A date mention as a small muted chip: calendar icon and "Tomorrow",
/// "Fri 14 Nov 09:30". Error tone once past, unless the item is checked.
/// Tap to change or remove it.
class DateEmbedBuilder extends EmbedBuilder {
  const DateEmbedBuilder();

  @override
  String get key => dateEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) =>
      dateMentionMarker(node.value.data as String);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final raw = embedContext.node.value.data as String;
    final mention = parseDateMention(raw);
    final c = Theme.of(context).colorScheme;
    final style = embedContext.textStyle;
    final size = (style.fontSize ?? 16) * 0.88;
    final text = mention == null
        ? raw
        : dateMentionLabel(context.l10n, mention, dateMentionNow());
    final overdue =
        mention != null &&
        dateMentionPast(mention, dateMentionNow()) &&
        !_inCheckedItem(
          embedContext.controller.document,
          embedContext.node.documentOffset,
        );
    final color = overdue ? c.error : c.onSurfaceVariant;
    return Semantics(
      button: !embedContext.readOnly,
      label: context.l10n.remindersLabel(text),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: embedContext.readOnly
            ? null
            : () => editDateMentionAt(
                context,
                embedContext.controller,
                embedContext.node.documentOffset,
              ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined, size: size, color: color),
              const SizedBox(width: 4),
              Text(
                text,
                style: style.copyWith(
                  fontSize: size,
                  color: color,
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

Embed? _dateAt(Document doc, int offset) {
  if (offset < 0 || offset >= doc.length) return null;
  final leaf = doc.querySegmentLeafNode(offset).leaf;
  if (leaf is Embed &&
      leaf.documentOffset == offset &&
      leaf.value.type == dateEmbedType) {
    return leaf;
  }
  return null;
}

/// Asks for a date (and optionally a time). Returns the text to store
/// (`2026-11-14` / `2026-11-14 09:30`), `''` to remove the mention, or null
/// when dismissed.
Future<String?> showDateMentionPicker(BuildContext context, {String? initial}) {
  Widget body(BuildContext context) => DateMentionPicker(initial: initial);
  if (isDesktop(context)) {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: body(context),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(child: body(context)),
  );
}

/// Today / Tomorrow / Next week / Pick a date…, and a time row.
class DateMentionPicker extends StatefulWidget {
  const DateMentionPicker({super.key, this.initial});

  /// The mention being changed, if any (then it can be removed).
  final String? initial;

  @override
  State<DateMentionPicker> createState() => _DateMentionPickerState();
}

class _DateMentionPickerState extends State<DateMentionPicker> {
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    final m = widget.initial == null ? null : parseDateMention(widget.initial!);
    if (m != null && m.hasTime) {
      _time = TimeOfDay(hour: m.hour!, minute: m.minute!);
    }
  }

  void _choose(DateTime date) => Navigator.pop(
    context,
    dateMentionRaw(date, hour: _time?.hour, minute: _time?.minute),
  );

  Future<void> _pickDate() async {
    final now = dateMentionNow();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.initial == null
          ? today
          : (parseDateMention(widget.initial!)?.date ?? today),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 20),
    );
    if (picked != null && mounted) _choose(picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = dateMentionNow();
    final today = DateTime(now.year, now.month, now.day);
    final dense = isDesktop(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('date-today'),
            dense: dense,
            leading: const Icon(Icons.today_outlined),
            title: Text(l10n.remindersToday),
            onTap: () => _choose(today),
          ),
          ListTile(
            key: const ValueKey('date-tomorrow'),
            dense: dense,
            leading: const Icon(Icons.event_outlined),
            title: Text(l10n.remindersTomorrow),
            onTap: () =>
                _choose(DateTime(today.year, today.month, today.day + 1)),
          ),
          ListTile(
            key: const ValueKey('date-next-week'),
            dense: dense,
            leading: const Icon(Icons.date_range_outlined),
            title: Text(l10n.remindersNextWeek),
            onTap: () =>
                _choose(DateTime(today.year, today.month, today.day + 7)),
          ),
          ListTile(
            key: const ValueKey('date-pick'),
            dense: dense,
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(l10n.remindersPickDate),
            onTap: _pickDate,
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('date-time'),
            dense: dense,
            leading: const Icon(Icons.schedule),
            title: Text(l10n.remindersTime),
            subtitle: Text(
              _time == null ? l10n.remindersNoTime : _time!.format(context),
            ),
            trailing: _time == null
                ? null
                : IconButton(
                    tooltip: l10n.commonRemove,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _time = null),
                  ),
            onTap: _pickTime,
          ),
          if (widget.initial != null)
            ListTile(
              key: const ValueKey('date-remove'),
              dense: dense,
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.commonRemove),
              onTap: () => Navigator.pop(context, ''),
            ),
        ],
      ),
    );
  }
}

/// Opens the picker for the mention at [offset] and writes the result back.
Future<void> editDateMentionAt(
  BuildContext context,
  QuillController controller,
  int offset,
) async {
  final leaf = _dateAt(controller.document, offset);
  if (leaf == null) return;
  final result = await showDateMentionPicker(
    context,
    initial: leaf.value.data as String,
  );
  if (result == null || _dateAt(controller.document, offset) == null) return;
  if (result.isEmpty) {
    controller.replaceText(
      offset,
      1,
      '',
      TextSelection.collapsed(offset: offset),
    );
  } else {
    controller.replaceText(
      offset,
      1,
      Embeddable(dateEmbedType, result),
      TextSelection.collapsed(offset: offset + 1),
    );
  }
}

/// Offers the picker for an `@` just typed at [at] (start of a line or after
/// a space, never in "and@or" or an email). Dismissing leaves the `@`.
bool dateTriggerAt(String text, int at) =>
    at < text.length &&
    text[at] == '@' &&
    (at == 0 || RegExp(r'\s').hasMatch(text[at - 1])) &&
    // "@{" is already a mention being typed by hand.
    !(at + 1 < text.length && text[at + 1] == '{');

Future<void> pickDateForAt(
  BuildContext context,
  QuillController controller,
  int at,
) async {
  final result = await showDateMentionPicker(context);
  if (result == null || result.isEmpty) return;
  final text = controller.document.toPlainText();
  if (at >= text.length || text[at] != '@') return;
  controller.replaceText(
    at,
    1,
    Embeddable(dateEmbedType, result),
    TextSelection.collapsed(offset: at + 1),
  );
}

/// `/` → Date reminder: inserts a mention at the cursor.
Future<void> insertDateMention(
  BuildContext context,
  QuillController controller,
) async {
  final result = await showDateMentionPicker(context);
  if (result == null || result.isEmpty) return;
  final doc = controller.document;
  final cursor = controller.selection.extentOffset;
  final index = cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor;
  controller.replaceText(
    index,
    0,
    Embeddable(dateEmbedType, result),
    TextSelection.collapsed(offset: index + 1),
  );
}
