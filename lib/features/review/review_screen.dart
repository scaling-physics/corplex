import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/haptics.dart';
import '../../theme/motion_widgets.dart';
import '../home/adaptive.dart' show ReadableColumn;
import '../library/all_highlights_screen.dart';
import '../library/paper_detail_screen.dart';
import '../library/pdf_viewer_screen.dart';
import 'review_schedule.dart';

/// "Revisit highlights": the passages that are due, one at a time. Keep
/// pushes a passage further out (1, 3, 7, 14, 30, 90 days), Skip asks again
/// tomorrow, Open in paper jumps to the page.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  // The queue is fixed when the screen opens, so acting on one card never
  // reshuffles the rest.
  List<HighlightWithPaper>? _queue;
  var _index = 0;
  var _kept = 0;

  void _open(HighlightWithPaper e) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => e.paper.pdfPath == null
            ? PaperDetailScreen(paperId: e.paper.id)
            : PdfViewerScreen(
                paperId: e.paper.id,
                pdfPath: e.paper.pdfPath!,
                initialPage: e.highlight.pageNumber,
              ),
      ),
    );
  }

  Future<void> _act(HighlightWithPaper e, {required bool keep}) async {
    final settings = ref.read(reviewSettingsProvider);
    if (keep) {
      AppHaptics.confirm();
      _kept++;
    }
    setState(() => _index++);
    if (keep) {
      await settings.keep(e.highlight.id);
    } else {
      await settings.skip(e.highlight.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(allHighlightsProvider);
    final settings = ref.watch(reviewSettingsProvider);

    if (_queue == null && all.hasValue && settings.loaded) {
      final list = all.value!;
      _queue = dueHighlights(
        list,
        settings.schedule,
        ref.read(reviewClockProvider)(),
      );
      Future.microtask(
        () => settings.prune({for (final e in list) e.highlight.id}),
      );
    }
    final queue = _queue;

    Widget body;
    if (queue == null) {
      body = const SizedBox.shrink();
    } else if (_index >= queue.length) {
      body = EmptyState(
        icon: Icons.check_circle_outline,
        title: queue.isEmpty
            ? context.l10n.reviewNothing
            : context.l10n.reviewCaughtUp,
        message: queue.isEmpty
            ? context.l10n.reviewEmptyMessage
            : _kept == 0
            ? context.l10n.reviewTomorrow
            : context.l10n.reviewLater,
      );
    } else {
      body = _Card(
        key: ValueKey(queue[_index].highlight.id),
        entry: queue[_index],
        position: context.l10n.reviewPosition(_index + 1, queue.length),
        onOpen: () => _open(queue[_index]),
        onKeep: () => _act(queue[_index], keep: true),
        onSkip: () => _act(queue[_index], keep: false),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.reviewTitle)),
      body: ReadableColumn(
        child: Column(
          children: [
            Expanded(
              child: StateSwitcher(stateKey: _index, child: body),
            ),
            SwitchListTile(
              title: Text(context.l10n.reviewRemind),
              subtitle: Text(context.l10n.reviewRemindHint),
              value: settings.remind,
              onChanged: settings.setRemind,
            ),
          ],
        ),
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.entry,
    required this.position,
    required this.onOpen,
    required this.onKeep,
    required this.onSkip,
  });

  final HighlightWithPaper entry;
  final String position;
  final VoidCallback onOpen;
  final VoidCallback onKeep;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = entry.highlight;
    final comment = (h.comment ?? '').trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        Text(
          position,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.reviewQuote(h.quote),
          style: theme.textTheme.titleLarge?.copyWith(
            fontStyle: FontStyle.italic,
            height: 1.4,
          ),
        ),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(comment, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 16),
        Text(
          context.l10n.reviewSource(entry.paper.title, h.pageNumber),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: onKeep,
              child: Text(context.l10n.reviewKeep),
            ),
            OutlinedButton(
              onPressed: onSkip,
              child: Text(context.l10n.reviewSkip),
            ),
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(context.l10n.reviewOpenInPaper),
            ),
          ],
        ),
      ],
    );
  }
}
