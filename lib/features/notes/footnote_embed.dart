import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';
import '../platform/mac_window.dart' show isDesktop;
import 'footnote_markers.dart';

/// Footnote numbers for one editor, live from its document.
///
/// A footnote's number is its place among the note's footnotes in document
/// order, so it changes when one is added, removed or moved. Chips listen
/// here and are told only when the footnotes' positions change. Footnotes
/// inside a collapsed section (a `fold` embed holding Delta JSON) still
/// count, so the numbers match what the note prints.
class FootnoteScope extends ChangeNotifier {
  FootnoteScope._(this._controller) {
    _controller.addListener(_changed);
    _rebuild();
  }

  static final _scopes = Expando<FootnoteScope>('footnote scope');

  /// The scope of [controller], made on first use (a note without
  /// footnotes never pays for one).
  static FootnoteScope of(QuillController controller) =>
      _scopes[controller] ??= FootnoteScope._(controller);

  final QuillController _controller;
  var _numbers = const <int, int>{};
  var _total = 0;

  /// How many footnotes the note has.
  int get total => _total;

  /// The number of the footnote at document [offset], or null.
  int? numberAt(int offset) => _numbers[offset];

  void _changed() {
    final before = _numbers;
    _rebuild();
    if (before.length != _numbers.length ||
        !before.entries.every((e) => _numbers[e.key] == e.value)) {
      notifyListeners();
    }
  }

  void _rebuild() {
    final numbers = <int, int>{};
    var count = 0;
    var offset = 0;
    for (final op in _controller.document.toDelta().toList()) {
      if (!op.isInsert) continue;
      final data = op.data;
      if (data is String) {
        offset += data.length;
        continue;
      }
      if (data is Map) {
        if (data.containsKey(footnoteEmbedType)) {
          numbers[offset] = ++count;
        } else if (data['fold'] != null) {
          count += _foldedFootnotes(data['fold']);
        }
      }
      offset += 1;
    }
    _numbers = numbers;
    _total = count;
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    super.dispose();
  }
}

/// Footnotes inside a collapsed section's saved lines.
int _foldedFootnotes(Object? data) {
  try {
    final ops = data is String ? jsonDecode(data) : data;
    if (ops is! List) return 0;
    var n = 0;
    for (final op in ops) {
      final insert = op is Map ? op['insert'] : null;
      if (insert is Map && insert.containsKey(footnoteEmbedType)) n++;
    }
    return n;
  } catch (_) {
    return 0;
  }
}

/// The footnote at [offset], if there still is one.
Embed? _footnoteAt(Document doc, int offset) {
  if (offset < 0 || offset >= doc.length) return null;
  final leaf = doc.querySegmentLeafNode(offset).leaf;
  if (leaf is Embed &&
      leaf.documentOffset == offset &&
      leaf.value.type == footnoteEmbedType) {
    return leaf;
  }
  return null;
}

/// A footnote as a small superscript number. Tap to edit; hovering or a
/// long press shows its text.
class FootnoteEmbedBuilder extends EmbedBuilder {
  const FootnoteEmbedBuilder();

  @override
  String get key => footnoteEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => footnoteMarker(node.value.data as String);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final text = embedContext.node.value.data as String;
    final scope = FootnoteScope.of(embedContext.controller);
    return ListenableBuilder(
      listenable: scope,
      builder: (context, _) {
        final offset = embedContext.node.documentOffset;
        final number = scope.numberAt(offset);
        final c = Theme.of(context).colorScheme;
        final shown = footnoteDisplayText(text);
        final style = embedContext.textStyle;
        return Semantics(
          button: !embedContext.readOnly,
          label: context.l10n.footnotesLabel('${number ?? '?'}'),
          child: Tooltip(
            message: shown.length > 280 ? '${shown.substring(0, 280)}…' : shown,
            waitDuration: const Duration(milliseconds: 500),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: embedContext.readOnly
                  ? null
                  : () => editFootnoteAt(
                      context,
                      embedContext.controller,
                      embedContext.node.documentOffset,
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: SizedBox(
                  height: (style.fontSize ?? 16) * 1.15,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      '${number ?? '?'}',
                      style: style.copyWith(
                        fontSize: (style.fontSize ?? 16) * 0.68,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        decoration: TextDecoration.none,
                        color: text.trim().isEmpty ? c.error : c.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Asks for a footnote's text. Returns the new text, `''` to remove the
/// footnote (also what clearing the field means), or null when dismissed.
Future<String?> showFootnoteEditor(
  BuildContext context, {
  String initial = '',
  bool canRemove = true,
}) {
  Widget body(BuildContext context) =>
      _FootnoteEditor(initial: initial, canRemove: canRemove);
  if (isDesktop(context)) {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
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
    builder: body,
  );
}

class _FootnoteEditor extends StatefulWidget {
  const _FootnoteEditor({required this.initial, required this.canRemove});

  final String initial;
  final bool canRemove;

  @override
  State<_FootnoteEditor> createState() => _FootnoteEditorState();
}

class _FootnoteEditorState extends State<_FootnoteEditor> {
  late final _text = TextEditingController(
    text: footnoteDisplayText(widget.initial),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('footnote-text'),
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(hintText: context.l10n.footnotesHint),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.canRemove)
                  TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: Text(context.l10n.commonRemove),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _text.text.trim()),
                  child: Text(context.l10n.commonDone),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The text to store for what the reader typed: brackets balanced.
String _stored(String typed) => balanceFootnoteText(typed);

/// Opens the editor for the footnote at [offset] and writes the result back.
Future<void> editFootnoteAt(
  BuildContext context,
  QuillController controller,
  int offset,
) async {
  final leaf = _footnoteAt(controller.document, offset);
  if (leaf == null) return;
  final result = await showFootnoteEditor(
    context,
    initial: leaf.value.data as String,
  );
  if (result == null) return;
  // Still there after the dialog (a sync may have moved things)?
  if (_footnoteAt(controller.document, offset) == null) return;
  if (result.isEmpty) {
    controller.replaceText(
      offset,
      1,
      '',
      TextSelection.collapsed(offset: offset),
    );
    return;
  }
  controller.replaceText(
    offset,
    1,
    Embeddable(footnoteEmbedType, _stored(result)),
    null,
  );
}

/// Inserts an empty footnote at the cursor (the `/` → "Footnote" command and
/// Format → Footnote) and opens its editor; cancelling removes it again.
Future<void> insertFootnote(
  BuildContext context,
  QuillController controller,
) async {
  final doc = controller.document;
  final cursor = controller.selection.extentOffset;
  final index = cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor;
  controller.replaceText(
    index,
    0,
    const Embeddable(footnoteEmbedType, ''),
    TextSelection.collapsed(offset: index + 1),
  );
  if (_footnoteAt(controller.document, index) == null) return;
  if (!context.mounted) return;
  final result = await showFootnoteEditor(context, canRemove: false);
  if (_footnoteAt(controller.document, index) == null) return;
  if (result == null || result.isEmpty) {
    controller.replaceText(
      index,
      1,
      '',
      TextSelection.collapsed(offset: index),
    );
  } else {
    controller.replaceText(
      index,
      1,
      Embeddable(footnoteEmbedType, _stored(result)),
      TextSelection.collapsed(offset: index + 1),
    );
  }
}
