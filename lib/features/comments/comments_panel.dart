import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../data/database.dart' show NoteComment;
import 'comment_anchor.dart';
import 'comment_views.dart';
import 'comments_data.dart';

/// The note's comments: open ones first (newest first), then resolved ones
/// behind a "Show resolved" toggle. Side panel on wide windows, the body of
/// a bottom sheet on phones — the editor decides; this is the content.
class CommentsPanel extends ConsumerStatefulWidget {
  const CommentsPanel({
    super.key,
    required this.noteId,
    required this.locate,
    required this.onPick,
    required this.onAdd,
    required this.onClose,
    required this.hasSelection,
    required this.onEdit,
    this.showClose = true,
  });

  final String noteId;

  /// Where the comment's passage is now; null when it can't be found.
  final CommentSpan? Function(CommentView) locate;

  /// Select the passage in the editor.
  final void Function(CommentView, CommentSpan) onPick;
  final VoidCallback onAdd;
  final VoidCallback onClose;
  final void Function(CommentView) onEdit;

  /// Whether text is selected in the editor (enables +).
  final ValueListenable<bool> hasSelection;
  final bool showClose;

  @override
  ConsumerState<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<CommentsPanel> {
  bool _showResolved = false;

  /// The comment just deleted, offered back inline: a snackbar would sit
  /// behind the bottom sheet on a phone.
  NoteComment? _deleted;

  Future<void> _delete(CommentView c) async {
    await ref.read(commentStoreProvider).delete(c.id);
    if (mounted) setState(() => _deleted = c.row);
  }

  Future<void> _undo() async {
    final row = _deleted;
    if (row == null) return;
    setState(() => _deleted = null);
    await ref.read(commentStoreProvider).restore(row);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final views = ref.watch(commentViewsProvider(widget.noteId));
    final all = views.value ?? const <CommentView>[];
    final open = [
      for (final c in all)
        if (!c.resolved) c,
    ];
    final resolved = [
      for (final c in all)
        if (c.resolved) c,
    ];
    final shown = [...open, if (_showResolved) ...resolved];
    return Material(
      key: const ValueKey('comments-panel'),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.commentsTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.hasSelection,
                  builder: (_, has, _) => IconButton(
                    key: const ValueKey('comments-add'),
                    tooltip: has
                        ? context.l10n.commentsOnSelection
                        : context.l10n.commentsSelectAPassage,
                    icon: const Icon(Icons.add_comment_outlined),
                    onPressed: has ? widget.onAdd : null,
                  ),
                ),
                if (widget.showClose)
                  IconButton(
                    key: const ValueKey('comments-close'),
                    tooltip: context.l10n.commonClose,
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          if (_deleted != null)
            ListTile(
              dense: true,
              title: Text(context.l10n.commentsDeleted),
              trailing: TextButton(
                onPressed: _undo,
                child: Text(context.l10n.commonUndo),
              ),
            ),
          if (resolved.isNotEmpty)
            SwitchListTile(
              key: const ValueKey('comments-show-resolved'),
              dense: true,
              title: Text(context.l10n.commentsShowResolved(resolved.length)),
              value: _showResolved,
              onChanged: (v) => setState(() => _showResolved = v),
            ),
          Flexible(
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      all.isEmpty
                          ? context.l10n.commentsEmpty
                          : context.l10n.commentsNothingOpen,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in shown)
                        _CommentTile(
                          key: ValueKey('comment-${c.id}'),
                          comment: c,
                          span: widget.locate(c),
                          onPick: widget.onPick,
                          onEdit: widget.onEdit,
                          onDelete: _delete,
                          onResolved: (c, v) => ref
                              .read(commentStoreProvider)
                              .setResolved(c.id, v),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.span,
    required this.onPick,
    required this.onEdit,
    required this.onDelete,
    required this.onResolved,
  });

  final CommentView comment;
  final CommentSpan? span;
  final void Function(CommentView, CommentSpan) onPick;
  final void Function(CommentView) onEdit;
  final void Function(CommentView) onDelete;
  final void Function(CommentView, bool) onResolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = comment;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final quote = displayQuote(c.quote);
    return InkWell(
      onTap: span == null ? null : () => onPick(c, span!),
      child: Opacity(
        opacity: c.resolved ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (quote.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: scheme.tertiary, width: 2),
                          ),
                        ),
                        child: Text(
                          quote,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(c.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (c.author != null) c.author!,
                        DateFormat.yMMMd(
                          Localizations.localeOf(context).toString(),
                        ).format(c.createdAt),
                        if (span == null) context.l10n.commentsPassageChanged,
                      ].join(' · '),
                      style: muted,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('comment-menu-${c.id}'),
                tooltip: context.l10n.commentsOptions,
                onSelected: (v) => switch (v) {
                  'resolve' => onResolved(c, true),
                  'reopen' => onResolved(c, false),
                  'edit' => onEdit(c),
                  _ => onDelete(c),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: c.resolved ? 'reopen' : 'resolve',
                    child: Text(
                      c.resolved
                          ? context.l10n.commentsReopen
                          : context.l10n.commentsResolve,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(context.l10n.commonEdit),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.l10n.commonDelete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
