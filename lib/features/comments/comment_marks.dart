import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'comment_anchor.dart';
import 'comments_data.dart';

/// Where the open comments of a note sit in the editor right now, and the
/// tint that marks them. The stored document is never touched: this only
/// wraps the editor's span builder.
class CommentMarks {
  CommentMarks(this.controller) {
    controller.addListener(_invalidate);
  }

  final QuillController controller;
  List<CommentView> _comments = const [];
  List<({CommentSpan span, List<CommentView> comments})>? _ranges;

  void dispose() => controller.removeListener(_invalidate);

  void _invalidate() => _ranges = null;

  /// Replaces the comments (no notification: called while building).
  void setComments(List<CommentView> comments) {
    _comments = comments;
    _ranges = null;
  }

  /// Open comments with their located passages, in document order. A
  /// comment whose passage can't be found has no mark.
  List<({CommentSpan span, List<CommentView> comments})> get ranges {
    final cached = _ranges;
    if (cached != null) return cached;
    final open = [
      for (final c in _comments)
        if (!c.resolved && c.quote.isNotEmpty) c,
    ];
    if (open.isEmpty) return _ranges = const [];
    final text = controller.document.toPlainText();
    final byStart = <String, List<CommentView>>{};
    final spans = <String, CommentSpan>{};
    for (final c in open) {
      final s = locate(text, c);
      if (s == null) continue;
      final k = '${s.start}:${s.end}';
      spans[k] = s;
      (byStart[k] ??= []).add(c);
    }
    final list = [
      for (final e in byStart.entries) (span: spans[e.key]!, comments: e.value),
    ]..sort((a, b) => a.span.start.compareTo(b.span.start));
    return _ranges = list;
  }

  static CommentSpan? locate(String text, CommentView c) =>
      locateQuote(text, c.quote, c.anchor);

  /// Comments whose passage covers [offset].
  List<CommentView> at(int offset) => [
    for (final r in ranges)
      if (offset >= r.span.start && offset < r.span.end) ...r.comments,
  ];

  /// [inner] (the spell checker's builder) with the comment tint added.
  /// A text run crossing a commented passage is split there and each piece
  /// goes through [inner], so spell-check underlines and the tint coexist.
  TextSpanBuilder wrap(TextSpanBuilder inner) {
    return (
      BuildContext context,
      Node node,
      int nodeOffset,
      String text,
      TextStyle? style,
      GestureRecognizer? recognizer,
    ) {
      if (text.isEmpty || _comments.isEmpty) {
        return inner(context, node, nodeOffset, text, style, recognizer);
      }
      final start = node.documentOffset + nodeOffset;
      final end = start + text.length;
      final hits = [
        for (final r in ranges)
          if (r.span.end > start && r.span.start < end) r.span,
      ];
      if (hits.isEmpty) {
        return inner(context, node, nodeOffset, text, style, recognizer);
      }
      final scheme = Theme.of(context).colorScheme;
      final tinted = (style ?? const TextStyle()).copyWith(
        backgroundColor: scheme.tertiary.withValues(alpha: 0.18),
      );
      final children = <InlineSpan>[];
      var at = 0;
      for (final h in hits) {
        final a = (h.start - start).clamp(0, text.length);
        final b = (h.end - start).clamp(0, text.length);
        if (a < at) continue; // overlapping marks: the first one wins
        if (a > at) {
          children.add(
            inner(
              context,
              node,
              nodeOffset + at,
              text.substring(at, a),
              style,
              recognizer,
            ),
          );
        }
        if (b > a) {
          children.add(
            inner(
              context,
              node,
              nodeOffset + a,
              text.substring(a, b),
              tinted,
              recognizer,
            ),
          );
        }
        at = b;
      }
      if (at < text.length) {
        children.add(
          inner(
            context,
            node,
            nodeOffset + at,
            text.substring(at),
            style,
            recognizer,
          ),
        );
      }
      return TextSpan(children: children);
    };
  }
}
