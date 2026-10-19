import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'comment_anchor.dart';
import 'comments_data.dart';

typedef CommentInput = ({String body, String? author});

/// Asks for a comment's text and, optionally, who made it ("Supervisor").
/// [suggestions] are authors used before.
Future<CommentInput?> showCommentDialog(
  BuildContext context, {
  required String quote,
  String initialBody = '',
  String? initialAuthor,
  List<String> suggestions = const [],
  bool editing = false,
}) {
  return showDialog<CommentInput>(
    context: context,
    builder: (_) => _CommentDialog(
      quote: quote,
      initialBody: initialBody,
      initialAuthor: initialAuthor,
      suggestions: suggestions,
      editing: editing,
    ),
  );
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({
    required this.quote,
    required this.initialBody,
    required this.initialAuthor,
    required this.suggestions,
    required this.editing,
  });

  final String quote;
  final String initialBody;
  final String? initialAuthor;
  final List<String> suggestions;
  final bool editing;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late final _body = TextEditingController(text: widget.initialBody);
  late final _author = TextEditingController(text: widget.initialAuthor ?? '');

  @override
  void dispose() {
    _body.dispose();
    _author.dispose();
    super.dispose();
  }

  void _save() {
    final body = _body.text.trim();
    if (body.isEmpty) return;
    final author = _author.text.trim();
    Navigator.pop(context, (
      body: body,
      author: author.isEmpty ? null : author,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = displayQuote(widget.quote);
    return AlertDialog(
      title: Text(
        widget.editing
            ? context.l10n.commentsEditComment
            : context.l10n.commentsAddComment,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (quote.isNotEmpty)
                Container(
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.tertiary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    quote,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('comment-body'),
                controller: _body,
                autofocus: true,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.l10n.commentsComment,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('comment-author'),
                controller: _author,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.l10n.commentsFromOptional,
                  hintText: context.l10n.commentsFromHint,
                ),
              ),
              if (widget.suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in widget.suggestions)
                      ActionChip(
                        label: Text(s),
                        onPressed: () => setState(() => _author.text = s),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('comment-save'),
          onPressed: _save,
          child: Text(
            widget.editing ? context.l10n.commonSave : context.l10n.commonAdd,
          ),
        ),
      ],
    );
  }
}

/// What the writer chose in the popover over a commented passage.
enum CommentChoice { resolve, edit, delete }

/// The comment(s) on a tapped passage, with Resolve / Edit / Delete.
Future<({CommentView comment, CommentChoice choice})?> showCommentPopover(
  BuildContext context,
  List<CommentView> comments,
) {
  return showDialog<({CommentView comment, CommentChoice choice})>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        key: const ValueKey('comment-popover'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in comments) ...[
                  if (c.author != null)
                    Text(c.author!, style: theme.textTheme.labelLarge),
                  Text(c.body, style: theme.textTheme.bodyMedium),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, (
                          comment: c,
                          choice: CommentChoice.resolve,
                        )),
                        child: Text(context.l10n.commentsResolve),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, (
                          comment: c,
                          choice: CommentChoice.edit,
                        )),
                        child: Text(context.l10n.commonEdit),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, (
                          comment: c,
                          choice: CommentChoice.delete,
                        )),
                        child: Text(context.l10n.commonDelete),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
