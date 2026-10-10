import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../../theme/app_theme.dart';
import 'highlights.dart';

/// Where one highlight sits in the document: its page, how far down that
/// page (0..1) and its ink.
typedef HighlightMark = ({int page, double y, Color color});

/// Every highlight of a paper as a [HighlightMark], decoded once per change
/// (the minimap and the page strip both read this).
final paperMarksProvider = StreamProvider.autoDispose
    .family<List<HighlightMark>, String>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.highlights,
      )..where((h) => h.paperId.equals(paperId))).watch().map(
        (rows) => [
          for (final h in rows)
            (
              page: h.pageNumber,
              y: decodeRects(h.rectsJson).firstOrNull?.top ?? 0.0,
              color: colorFromHex(h.colorHex),
            ),
        ],
      );
    });

/// "3 / 24": where the reader is. Tapping it opens the page strip.
class PageIndicator extends StatelessWidget {
  const PageIndicator({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onTap,
  });

  final ValueListenable<int> page;
  final int pageCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: page,
          builder: (_, value, _) => Text(
            '$value / $pageCount',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: c.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// A row of small page thumbnails to scrub through the document. Pages
/// that hold highlights carry a dot in each ink used. Thumbnails are built
/// lazily by [thumbnail] as they scroll into view.
class PageStrip extends StatefulWidget {
  const PageStrip({
    super.key,
    required this.pageCount,
    required this.current,
    required this.marks,
    required this.onJump,
    required this.thumbnail,
  });

  static const itemWidth = 64.0;
  static const height = 100.0;

  final int pageCount;
  final ValueListenable<int> current;
  final List<HighlightMark> marks;
  final ValueChanged<int> onJump;
  final Widget Function(BuildContext context, int page) thumbnail;

  @override
  State<PageStrip> createState() => _PageStripState();
}

class _PageStripState extends State<PageStrip> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Open centred on the current page.
    _scroll = ScrollController(
      initialScrollOffset: ((widget.current.value - 1) * PageStrip.itemWidth)
          .clamp(0, double.infinity),
    );
    widget.current.addListener(_follow);
  }

  @override
  void dispose() {
    widget.current.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current page in view as the reader scrolls the document.
  void _follow() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final left = (widget.current.value - 1) * PageStrip.itemWidth;
    final visibleLeft = pos.pixels;
    final visibleRight = pos.pixels + pos.viewportDimension;
    if (left >= visibleLeft && left + PageStrip.itemWidth <= visibleRight) {
      return;
    }
    final target = (left - (pos.viewportDimension - PageStrip.itemWidth) / 2)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (AppMotion.reduced(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: AppMotion.short,
        curve: AppMotion.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final inks = <int, List<Color>>{};
    for (final m in widget.marks) {
      final list = inks.putIfAbsent(m.page, () => []);
      if (!list.contains(m.color) && list.length < 3) list.add(m.color);
    }
    return Material(
      color: c.surfaceContainerHigh,
      child: SizedBox(
        height: PageStrip.height,
        child: ValueListenableBuilder<int>(
          valueListenable: widget.current,
          builder: (context, current, _) => ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            itemExtent: PageStrip.itemWidth,
            itemCount: widget.pageCount,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, i) {
              final page = i + 1;
              final selected = page == current;
              return InkWell(
                key: ValueKey('strip-page-$page'),
                onTap: () => widget.onJump(page),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selected ? c.primary : c.outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: widget.thumbnail(context, page),
                        ),
                      ),
                      SizedBox(
                        height: 14,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final color in inks[page] ?? const <Color>[])
                              Container(
                                key: const ValueKey('strip-dot'),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (inks[page] == null)
                              Text(
                                '$page',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: c.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Thin ticks down the right edge, one per highlight, at the highlight's
/// place in the document. Only the ticks take touches; everywhere else the
/// reader's pan, zoom and selection gestures pass straight through.
class HighlightMinimap extends StatelessWidget {
  const HighlightMinimap({
    super.key,
    required this.pageCount,
    required this.marks,
    required this.onJump,
  });

  final int pageCount;
  final List<HighlightMark> marks;
  final ValueChanged<int> onJump;

  /// Fraction down the document (0..1) of [mark], pages being equal height.
  static double position(HighlightMark mark, int pageCount) =>
      ((mark.page - 1 + mark.y) / pageCount).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty || pageCount <= 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        const tickHeight = 4.0;
        const hit = 18.0;
        final usable = box.maxHeight - tickHeight;
        // One tick per 6 px: a page full of highlights is one tick, not a
        // hundred overlapping widgets.
        final seen = <int>{};
        final ticks = <Widget>[];
        for (final mark in marks) {
          final top = position(mark, pageCount) * usable;
          if (!seen.add((top / 6).floor())) continue;
          ticks.add(
            Positioned(
              key: ValueKey('minimap-tick-${mark.page}-${(top).round()}'),
              right: 0,
              top: top + tickHeight / 2 - hit / 2,
              width: 22,
              height: hit,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onJump(mark.page),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 8,
                    height: tickHeight,
                    decoration: BoxDecoration(
                      color: mark.color,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.shadow
                              .withValues(alpha: 0.25),
                          blurRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(children: ticks);
      },
    );
  }
}
