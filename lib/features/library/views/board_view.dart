import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database.dart';
import '../../../data/database_provider.dart';
import '../../../data/tables/papers_table.dart' show ReadingStatus;
import '../../../l10n/l10n.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/context_menu.dart';
import '../../../theme/haptics.dart';
import '../../platform/mac_window.dart';
import '../authors.dart';
import '../paper_cover.dart';
import '../papers_providers.dart';
import 'views_model.dart';

String boardColumnTitle(BuildContext context, ReadingStatus? s) => s == null
    ? context.l10n.viewsNoStatus
    : readingStatusLabel(context.l10n, s);

/// Sets [paper]'s status (one write, a tick) with an Undo snackbar.
Future<void> movePaperToStatus(
  BuildContext context,
  WidgetRef ref,
  Paper paper,
  ReadingStatus? to,
) async {
  if (paper.readingStatus == to) return;
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final before = paper.readingStatus;
  AppHaptics.selection();
  await setReadingStatus(db, paper.id, to);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          l10n.viewsMovedTo(
            paper.title,
            to == null ? l10n.viewsNoStatus : readingStatusLabel(l10n, to),
          ),
        ),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => setReadingStatus(db, paper.id, before),
        ),
      ),
    );
}

/// The Library as three columns by reading status. Drag a card to another
/// column to change its status; phones swipe between columns and use a
/// small menu instead.
class ReadingBoard extends ConsumerWidget {
  const ReadingBoard({super.key, required this.papers, required this.onOpen});

  final List<Paper> papers;
  final void Function(Paper paper) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = boardColumns(papers);
    final width = MediaQuery.sizeOf(context).width;
    Widget column(BoardColumn c, {double? w}) => _Column(
      key: ValueKey('board-col-${c.status?.name ?? 'none'}'),
      column: c,
      width: w,
      onOpen: onOpen,
    );
    if (width < 600) {
      return PageView(
        key: const ValueKey('board-pages'),
        controller: PageController(viewportFraction: 0.92),
        padEnds: false,
        children: [
          for (final c in columns)
            Padding(padding: const EdgeInsets.only(left: 12), child: column(c)),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const minW = 250.0;
        final fits = box.maxWidth - 32 >= columns.length * (minW + 12);
        if (fits) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: Row(
              children: [
                for (final c in columns) Expanded(child: _gap(column(c))),
              ],
            ),
          );
        }
        return ListView(
          key: const ValueKey('board-scroll'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          children: [for (final c in columns) _gap(column(c, w: 280))],
        );
      },
    );
  }

  Widget _gap(Widget child) =>
      Padding(padding: const EdgeInsets.only(right: 12), child: child);
}

class _Column extends ConsumerWidget {
  const _Column({
    super.key,
    required this.column,
    required this.onOpen,
    this.width,
  });

  final BoardColumn column;
  final double? width;
  final void Function(Paper paper) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return DragTarget<Paper>(
      onWillAcceptWithDetails: (d) => d.data.readingStatus != column.status,
      onAcceptWithDetails: (d) =>
          movePaperToStatus(context, ref, d.data, column.status),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.short),
        width: width,
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? c.surfaceContainerLow
              : c.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Text(
                '${boardColumnTitle(context, column.status)}  '
                '${column.papers.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: c.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                itemCount: column.papers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _BoardCard(
                  key: ValueKey('board-card-${column.papers[i].id}'),
                  paper: column.papers[i],
                  onOpen: onOpen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardCard extends ConsumerWidget {
  const _BoardCard({super.key, required this.paper, required this.onOpen});

  final Paper paper;
  final void Function(Paper paper) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = isDesktop(context);
    final card = _CardBody(
      paper: paper,
      trailing: desktop
          ? null
          : PopupMenuButton<ReadingStatus?>(
              key: ValueKey('board-move-${paper.id}'),
              tooltip: context.l10n.viewsMoveTo,
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.more_vert),
              onSelected: (s) => movePaperToStatus(context, ref, paper, s),
              itemBuilder: (_) => [
                for (final s in ReadingStatus.values)
                  if (s != paper.readingStatus)
                    PopupMenuItem(
                      value: s,
                      child: Text(readingStatusLabel(context.l10n, s)),
                    ),
              ],
            ),
      onTap: () => onOpen(paper),
    );
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: 240, child: Opacity(opacity: 0.9, child: card)),
    );
    final dim = Opacity(opacity: 0.35, child: card);
    final Widget draggable = desktop
        ? Draggable<Paper>(
            data: paper,
            feedback: feedback,
            childWhenDragging: dim,
            child: card,
          )
        : LongPressDraggable<Paper>(
            data: paper,
            feedback: feedback,
            childWhenDragging: dim,
            child: card,
          );
    if (!desktop) return draggable;
    return ContextMenuRegion(
      actions: [
        for (final s in ReadingStatus.values)
          if (s != paper.readingStatus)
            ContextMenuAction(
              label: context.l10n.viewsMoveToStatus(
                readingStatusLabel(context.l10n, s),
              ),
              onSelected: () => movePaperToStatus(context, ref, paper, s),
            ),
      ],
      child: draggable,
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.paper, required this.onTap, this.trailing});

  final Paper paper;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final authors = displayAuthors(paper.authors, max: 2);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperCover(paperId: paper.id, pdfPath: paper.pdfPath, width: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paper.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                    if (authors.isNotEmpty)
                      Text(
                        authors,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    if (paper.rating != null)
                      Text(
                        '★' * paper.rating!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.primary,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
