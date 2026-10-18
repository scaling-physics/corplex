import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lock/note_lock_service.dart';
import 'comment_anchor.dart';
import 'comment_dialogs.dart';
import 'comment_marks.dart';
import 'comments_data.dart';
import 'comments_panel.dart';

/// Everything the note editor needs for comments, in one object: the tint
/// on commented passages, adding from a selection, the tap popover, the
/// context-menu item and the panel (side or sheet). The editor owns one.
class EditorComments {
  EditorComments({
    required this.noteId,
    required this.controller,
    required this.ref,
  }) : marks = CommentMarks(controller) {
    controller.addListener(_selectionChanged);
    _selectionChanged();
  }

  final String noteId;
  final QuillController controller;
  final WidgetRef ref;
  final CommentMarks marks;

  /// Whether text is selected (the panel's + follows it).
  final hasSelection = ValueNotifier<bool>(false);

  void _selectionChanged() {
    final s = controller.selection;
    final has = s.isValid && !s.isCollapsed;
    if (hasSelection.value != has) hasSelection.value = has;
  }

  void dispose() {
    controller.removeListener(_selectionChanged);
    marks.dispose();
    hasSelection.dispose();
  }

  /// Call from build: the comments to mark.
  void sync(AsyncValue<List<CommentView>> views) {
    marks.setComments(views.value ?? const []);
  }

  CommentSpan? locate(CommentView c) =>
      CommentMarks.locate(controller.document.toPlainText(), c);

  /// Selects the passage (the editor scrolls to its selection).
  void select(CommentSpan span) {
    controller.updateSelection(
      TextSelection(baseOffset: span.start, extentOffset: span.end),
      ChangeSource.local,
    );
  }

  /// Asks for a comment on the current selection and stores it. Returns
  /// false if nothing is selected (nothing happens).
  Future<bool> addFromSelection(BuildContext context) async {
    final sel = controller.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final text = controller.document.toPlainText();
    var start = sel.start.clamp(0, text.length);
    var end = sel.end.clamp(0, text.length);
    bool blank(int i) => text[i].trim().isEmpty && text[i] != '￼';
    // Trim blanks at the edges so the quote is the passage that reads as
    // selected; the anchor moves with it.
    while (start < end && blank(start)) {
      start++;
    }
    while (end > start && blank(end - 1)) {
      end--;
    }
    if (start >= end) return false;
    final quote = text.substring(start, end);
    final store = ref.read(commentStoreProvider);
    final suggestions = await store.recentAuthors();
    if (!context.mounted) return true;
    final input = await showCommentDialog(
      context,
      quote: quote,
      suggestions: suggestions,
    );
    if (input == null) return true;
    try {
      await store.add(
        noteId: noteId,
        quote: quote,
        anchor: start,
        body: input.body,
        author: input.author,
      );
    } on NoteLockedException {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Unlock your notes to add a comment.')),
        );
      }
    }
    return true;
  }

  Future<void> edit(BuildContext context, CommentView c) async {
    final store = ref.read(commentStoreProvider);
    final suggestions = await store.recentAuthors();
    if (!context.mounted) return;
    final input = await showCommentDialog(
      context,
      quote: c.quote,
      initialBody: c.body,
      initialAuthor: c.author,
      suggestions: suggestions,
      editing: true,
    );
    if (input == null) return;
    try {
      await store.edit(c, body: input.body, author: input.author);
    } on NoteLockedException {
      // Locked again meanwhile; nothing to save.
    }
  }

  /// Editor `onTapUp`: tapping a commented passage shows its comments.
  /// Always returns false so the editor still places the caret.
  bool onTapUp(
    BuildContext context,
    TapUpDetails details,
    TextPosition Function(Offset) positionFor,
  ) {
    if (marks.ranges.isEmpty) return false;
    final hits = marks.at(positionFor(details.globalPosition).offset);
    if (hits.isEmpty) return false;
    Future.microtask(() async {
      if (!context.mounted) return;
      final r = await showCommentPopover(context, hits);
      if (r == null || !context.mounted) return;
      final store = ref.read(commentStoreProvider);
      switch (r.choice) {
        case CommentChoice.resolve:
          await store.setResolved(r.comment.id, true);
        case CommentChoice.edit:
          await edit(context, r.comment);
        case CommentChoice.delete:
          await store.delete(r.comment.id);
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: const Text('Comment deleted'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => store.restore(r.comment.row),
                ),
              ),
            );
          }
      }
    });
    return false;
  }

  /// The context menu: [inner] (the spell checker's), with "Add comment"
  /// among the editor's own items when text is selected. While [innerWins]
  /// (a misspelling is selected) the spell menu is left alone.
  Widget contextMenu(
    BuildContext context,
    QuillRawEditorState state,
    Widget Function(BuildContext, QuillRawEditorState) inner, {
    bool Function()? innerWins,
  }) {
    final sel = controller.selection;
    if (!sel.isValid || sel.isCollapsed || (innerWins?.call() ?? false)) {
      return inner(context, state);
    }
    return TextFieldTapRegion(
      child: AdaptiveTextSelectionToolbar.buttonItems(
        buttonItems: [
          ...state.contextMenuButtonItems,
          ContextMenuButtonItem(
            label: 'Add comment',
            onPressed: () {
              state.hideToolbar();
              addFromSelection(context);
            },
          ),
        ],
        anchors: state.contextMenuAnchors,
      ),
    );
  }

  /// The panel (side panel or sheet content). [afterPick] runs once the
  /// passage is selected.
  Widget panel({
    required VoidCallback onClose,
    required BuildContext context,
    void Function(CommentSpan)? afterPick,
    bool showClose = true,
  }) {
    return CommentsPanel(
      noteId: noteId,
      locate: locate,
      hasSelection: hasSelection,
      showClose: showClose,
      onClose: onClose,
      onAdd: () => addFromSelection(context),
      onEdit: (c) => edit(context, c),
      onPick: (c, span) {
        select(span);
        afterPick?.call(span);
      },
    );
  }
}
