import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../theme/app_theme.dart';
import '../../theme/context_menu.dart';
import 'authors.dart';
import 'paper_cover.dart';

/// The Library as a grid of covers (pinch out on a trackpad, or ⋮ → Show as
/// grid), for browsing by looks. Tapping opens the paper like a row does.
class LibraryGrid extends ConsumerWidget {
  const LibraryGrid({
    super.key,
    required this.papers,
    required this.selectedId,
    required this.onOpen,
    this.actionsFor,
  });

  final List<Paper> papers;
  final String? selectedId;
  final void Function(Paper paper) onOpen;

  /// Right-click actions (desktop).
  final List<ContextMenuAction?> Function(Paper paper)? actionsFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      key: const ValueKey('library-grid'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 16,
        crossAxisSpacing: 14,
        mainAxisExtent: 270,
      ),
      itemCount: papers.length,
      itemBuilder: (context, i) {
        final paper = papers[i];
        final tile = _GridTile(
          paper: paper,
          selected: paper.id == selectedId,
          onTap: () => onOpen(paper),
        );
        final actions = actionsFor?.call(paper);
        return actions == null
            ? tile
            : ContextMenuRegion(actions: actions, child: tile);
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.paper,
    required this.selected,
    required this.onTap,
  });

  final Paper paper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final byline = [
      if (paper.authors.isNotEmpty) displayAuthors(paper.authors, max: 1),
      if (paper.year case final year?) '$year',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.short),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? c.primaryContainer.withValues(alpha: 0.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Align(
                  alignment: Alignment.topCenter,
                  child: ClipRect(
                    child: PaperCover(
                      paperId: paper.id,
                      pdfPath: paper.pdfPath,
                      width: box.maxWidth,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              paper.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
            if (byline.isNotEmpty)
              Text(
                byline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: c.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
