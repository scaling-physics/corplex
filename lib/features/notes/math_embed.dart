import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import 'citation_embed.dart' show FreshCitations;
import 'math_markers.dart';

/// True when [tex] parses. Invalid LaTeX is never an error for the reader:
/// it stays as written and shows as plain source.
bool isValidTex(String tex) => Math.tex(tex).parseError == null;

const _monoFallback = ['Menlo', 'Roboto Mono', 'monospace'];

/// The drawn equation, or the raw source in a calm tone if it won't parse.
Widget mathView(
  BuildContext context,
  String latex, {
  required bool display,
  TextStyle? textStyle,
}) {
  final c = Theme.of(context).colorScheme;
  final base = textStyle ?? DefaultTextStyle.of(context).style;
  return Math.tex(
    latex,
    mathStyle: display ? MathStyle.display : MathStyle.text,
    textStyle: base.copyWith(color: c.onSurface),
    onErrorFallback: (_) => Text(
      latex,
      style: base.copyWith(color: c.outline, fontFamilyFallback: _monoFallback),
    ),
  );
}

/// Chips and blocks the user has just inserted play a small pop-in; those
/// of a loaded note don't. Shares the mark/take mechanism of citation chips.
class _Pop extends StatefulWidget {
  const _Pop({required this.node, required this.child});

  final Node node;
  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: 1,
  );
  bool _pending = false;

  void _start() {
    if (!_pending) return;
    _pending = false;
    if (!AppMotion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _pending = FreshCitations.take(widget.node);
  }

  @override
  void didUpdateWidget(_Pop old) {
    super.didUpdateWidget(old);
    if (!identical(old.node, widget.node) && FreshCitations.take(widget.node)) {
      _pending = true;
      _start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: AppMotion.enter);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(a),
        child: widget.child,
      ),
    );
  }
}

/// Renders inline `$…$` maths as a chip. Tap to edit.
class MathInlineEmbedBuilder extends EmbedBuilder {
  const MathInlineEmbedBuilder();

  @override
  String get key => mathInlineType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => inlineMathMarker(node.value.data as String);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final latex = embedContext.node.value.data as String;
    final c = Theme.of(context).colorScheme;
    return _Pop(
      node: embedContext.node,
      child: Semantics(
        button: !embedContext.readOnly,
        label: context.l10n.notesEquationLabel(latex),
        child: GestureDetector(
          onTap: embedContext.readOnly
              ? null
              : () => editMathAt(
                  context,
                  embedContext.controller,
                  embedContext.node.documentOffset,
                ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: c.surfaceContainerHigh.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: mathView(
              context,
              latex,
              display: false,
              textStyle: embedContext.textStyle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders display maths (`$$…$$` on its own line) centred in a block.
class MathBlockEmbedBuilder extends EmbedBuilder {
  const MathBlockEmbedBuilder();

  @override
  String get key => mathBlockType;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) =>
      displayMathMarker(node.value.data as String);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final latex = embedContext.node.value.data as String;
    final c = Theme.of(context).colorScheme;
    return _Pop(
      node: embedContext.node,
      child: Semantics(
        button: !embedContext.readOnly,
        label: context.l10n.notesEquationLabel(latex),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: embedContext.readOnly
              ? null
              : () => editMathAt(
                  context,
                  embedContext.controller,
                  embedContext.node.documentOffset,
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: latex.trim().isEmpty
                    ? Text(
                        context.l10n.notesEquationEmpty,
                        style: TextStyle(color: c.outline),
                      )
                    : mathView(
                        context,
                        latex,
                        display: true,
                        textStyle: embedContext.textStyle.copyWith(
                          fontSize:
                              (embedContext.textStyle.fontSize ?? 16) * 1.15,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet for writing LaTeX: a field and a live preview. Returns the
/// new source, `''` for "Remove", or null when dismissed.
Future<String?> showMathEditor(
  BuildContext context, {
  String initial = '',
  bool display = false,
  bool canRemove = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _MathEditor(initial: initial, display: display, canRemove: canRemove),
  );
}

class _MathEditor extends StatefulWidget {
  const _MathEditor({
    required this.initial,
    required this.display,
    required this.canRemove,
  });

  final String initial;
  final bool display;
  final bool canRemove;

  @override
  State<_MathEditor> createState() => _MathEditorState();
}

class _MathEditorState extends State<_MathEditor> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final latex = _text.text.trim();
    final valid = latex.isEmpty || isValidTex(latex);
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
            Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: latex.isEmpty
                  ? Text(
                      context.l10n.notesPreview,
                      style: TextStyle(color: c.outline),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: mathView(
                        context,
                        latex,
                        display: widget.display,
                        textStyle: tt.titleLarge,
                      ),
                    ),
            ),
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.short),
              child: valid
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text(
                        context.l10n.notesLatexInvalid,
                        style: tt.bodySmall?.copyWith(color: c.outline),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamilyFallback: _monoFallback),
              decoration: InputDecoration(
                hintText: context.l10n.notesLatexHint,
              ),
              onChanged: (_) => setState(() {}),
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

/// The maths embed at [offset], if there still is one.
Embed? _mathLeafAt(Document doc, int offset) {
  if (offset < 0 || offset >= doc.length) return null;
  final leaf = doc.querySegmentLeafNode(offset).leaf;
  if (leaf is Embed &&
      leaf.documentOffset == offset &&
      (leaf.value.type == mathInlineType || leaf.value.type == mathBlockType)) {
    return leaf;
  }
  return null;
}

/// Opens the editor for the maths at [offset] and writes the result back.
Future<void> editMathAt(
  BuildContext context,
  QuillController controller,
  int offset,
) async {
  final leaf = _mathLeafAt(controller.document, offset);
  if (leaf == null) return;
  final type = leaf.value.type;
  final result = await showMathEditor(
    context,
    initial: leaf.value.data as String,
    display: type == mathBlockType,
  );
  if (result == null) return;
  // Still there after the sheet (a sync may have moved things)?
  final now = _mathLeafAt(controller.document, offset);
  if (now == null || now.value.type != type) return;
  if (result.isEmpty) {
    controller.replaceText(
      offset,
      1,
      '',
      TextSelection.collapsed(offset: offset),
    );
    return;
  }
  controller.replaceText(offset, 1, _embed(type, result), null);
}

Embeddable _embed(String type, String latex) => type == mathBlockType
    // Inserted directly, never BlockEmbed.custom (see the sketch embed).
    ? CustomBlockEmbed(type, latex)
    : Embeddable(type, latex);

void _markFresh(QuillController controller, int index) {
  final at = controller.document.queryChild(index);
  final line = at.node;
  if (line is Line) {
    final leaf = line.queryChild(at.offset, false).node;
    if (leaf != null) FreshCitations.mark(leaf);
  }
}

/// Inserts a display-maths block at the cursor (the `/` → "Equation"
/// command) and opens its editor; cancelling removes it again.
Future<void> insertDisplayMath(
  BuildContext context,
  QuillController controller,
) async {
  final doc = controller.document;
  final cursor = controller.selection.baseOffset;
  final index = cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor;
  await _insertBlockAndEdit(context, controller, index, 0);
}

Future<void> _insertBlockAndEdit(
  BuildContext context,
  QuillController controller,
  int index,
  int replacing,
) async {
  controller.replaceText(
    index,
    replacing,
    const CustomBlockEmbed(mathBlockType, ''),
    TextSelection.collapsed(offset: index + 1),
  );
  int? at;
  for (final candidate in [index, index + 1]) {
    if (_mathLeafAt(controller.document, candidate)?.value.type ==
        mathBlockType) {
      at = candidate;
      break;
    }
  }
  if (at == null) return;
  _markFresh(controller, at);
  if (!context.mounted) return;
  final result = await showMathEditor(context, display: true, canRemove: false);
  final still = _mathLeafAt(controller.document, at);
  if (still == null || still.value.type != mathBlockType) return;
  if (result == null || result.isEmpty) {
    controller.replaceText(at, 1, '', TextSelection.collapsed(offset: at));
  } else {
    controller.replaceText(
      at,
      1,
      CustomBlockEmbed(mathBlockType, result),
      null,
    );
  }
}

/// Called after the user types a `$` at [at]: turns a finished `$…$` into a
/// chip, or a line of `$$` into a display block (and opens its editor).
/// Returns true if it changed the document.
bool convertTypedDollar(
  BuildContext context,
  QuillController controller,
  int at,
) {
  final text = controller.document.toPlainText();
  if (at < 0 || at >= text.length || text[at] != r'$') return false;
  final ls = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
  var le = text.indexOf('\n', at);
  if (le < 0) le = text.length;
  final line = text.substring(ls, le);

  if (line == r'$$' && at == ls + 1) {
    Future.microtask(() {
      if (context.mounted) _insertBlockAndEdit(context, controller, ls, 2);
    });
    return true;
  }
  // Inside inline code a dollar is just a dollar.
  final style = controller.document.collectStyle(at, 1);
  if (style.attributes.containsKey('code') ||
      style.attributes.containsKey('code-block')) {
    return false;
  }
  for (final m in findInlineMath(line)) {
    if (m.end != at - ls + 1) continue;
    Future.microtask(() {
      final start = ls + m.start;
      // Make sure nothing moved in between.
      final now = controller.document.toPlainText();
      if (now.length < start + m.end - m.start ||
          now.substring(start, ls + m.end) != '\$${m.latex}\$') {
        return;
      }
      controller.replaceText(
        start,
        m.end - m.start,
        Embeddable(mathInlineType, m.latex),
        TextSelection.collapsed(offset: start + 1),
      );
      _markFresh(controller, start);
    });
    return true;
  }
  return false;
}
