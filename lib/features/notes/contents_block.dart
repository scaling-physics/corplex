import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../l10n/l10n.dart';
import 'heading_fold_ui.dart';
import 'note_sections.dart';

/// An inline table of contents: a block embed `contents` on a line of its
/// own that lists the note's headings, live. It holds nothing (`{}`): the
/// list is read from the document every time, so it can never go stale.
/// Exports write the headings as a plain list instead
/// ([contentsLines]); word count and search ignore it.
const contentsEmbedType = 'contents';

/// The headings a contents block lists in [delta] (editor or stored form):
/// every heading with text, in order. The block's own line is ignored.
List<NoteHeading> contentsEntries(Delta delta) => headingsOf(docLines(delta));

/// The plain-text lines an export writes for a contents block: the heading
/// titles, indented two spaces per level below the first.
List<String> contentsLines(Delta delta) {
  final entries = contentsEntries(delta);
  if (entries.isEmpty) return const [];
  final top = entries.map((e) => e.level).reduce((a, b) => a < b ? a : b);
  return [for (final e in entries) '${'  ' * (e.level - top)}${e.text}'];
}

/// Inserts a contents block at the cursor on a line of its own (the text
/// around it stays on lines of its own). Quill only adds the newlines around
/// a block embed for videos, so they are added here.
void insertContentsAtCursor(QuillController controller) {
  final doc = controller.document;
  final cursor = controller.selection.baseOffset;
  final at = (cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor)
      .clamp(0, doc.length - 1);
  final plain = doc.toPlainText();
  final lineStart = at == 0 || plain[at - 1] == '\n';
  final lineEnd = plain[at] == '\n';
  final delta = Delta()..retain(at);
  if (!lineStart) delta.insert('\n');
  delta.insert(CustomBlockEmbed(contentsEmbedType, '{}').toJson());
  if (!lineEnd) delta.insert('\n');
  final landed = (lineStart ? at : at + 1) + 1;
  controller.compose(
    delta,
    TextSelection.collapsed(offset: landed.clamp(0, doc.length + delta.length)),
    ChangeSource.local,
  );
}

class ContentsEmbedBuilder extends EmbedBuilder {
  /// [onJump] is what a tap on a heading does: the editor moves the caret
  /// there, opening any fold that hides it.
  const ContentsEmbedBuilder({this.onJump});

  final void Function(NoteHeading heading)? onJump;

  @override
  String get key => contentsEmbedType;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      _ContentsView(controller: embedContext.controller, onJump: onJump);
}

class _ContentsView extends StatefulWidget {
  const _ContentsView({required this.controller, this.onJump});

  final QuillController controller;
  final void Function(NoteHeading heading)? onJump;

  @override
  State<_ContentsView> createState() => _ContentsViewState();
}

class _ContentsViewState extends State<_ContentsView> {
  StreamSubscription<DocChange>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.document.changes.listen(_changed);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Document changes arrive as a stream; rebuild only when the headings are
  // different from what is shown.
  List<String> _shown = const [];

  void _changed(DocChange _) {
    if (!mounted) return;
    final now = _entries().map((e) => '${e.level}${e.text}').toList();
    if (now.length != _shown.length ||
        List.generate(now.length, (i) => now[i] != _shown[i]).any((b) => b)) {
      setState(() {});
    }
  }

  List<NoteHeading> _entries() {
    final folds = HeadingFoldScope.maybeOf(context);
    final delta =
        folds?.unfoldedDocument().toDelta() ??
        widget.controller.document.toDelta();
    return contentsEntries(delta);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    _shown = entries.map((e) => '${e.level}${e.text}').toList();
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodyMedium?.copyWith(color: color);
    final onJump = widget.onJump;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(context.l10n.blocksContentsEmpty, style: style),
      );
    }
    final top = entries.map((e) => e.level).reduce((a, b) => a < b ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Semantics(
              button: true,
              child: InkWell(
                // The editor also places the caret at the tapped embed; jump after
                // that, or it would win.
                onTap: onJump == null
                    ? null
                    : () => WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onJump(e),
                      ),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 16.0 * (e.level - top),
                    top: 2,
                    bottom: 2,
                  ),
                  child: Text(e.text, style: style),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
