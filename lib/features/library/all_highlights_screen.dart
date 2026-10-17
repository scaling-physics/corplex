import 'package:drift/drift.dart' show OrderingTerm, innerJoin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/adaptive.dart' show ReadableColumn;
import '../platform/mac_window.dart';
import '../../theme/context_menu.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/motion_widgets.dart';
import 'paper_detail_screen.dart';
import 'pdf_viewer_screen.dart';
import '../review/review_screen.dart';

/// A highlight together with the paper it came from.
typedef HighlightWithPaper = ({Highlight highlight, Paper paper});

/// Every highlight in the library, grouped by paper (alphabetical, pages in
/// order), newest edit wins nothing here — it's a reading list of passages.
final allHighlightsProvider =
    StreamProvider.autoDispose<List<HighlightWithPaper>>((ref) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.highlights).join([
            innerJoin(db.papers, db.papers.id.equalsExp(db.highlights.paperId)),
          ])..orderBy([
            OrderingTerm.asc(db.papers.title),
            OrderingTerm.asc(db.highlights.pageNumber),
            OrderingTerm.asc(db.highlights.createdAt),
          ]);
      return query.watch().map(
        (rows) => [
          for (final r in rows)
            (
              highlight: r.readTable(db.highlights),
              paper: r.readTable(db.papers),
            ),
        ],
      );
    });

/// Keeps the entries whose quote, comment or paper title contain [query].
List<HighlightWithPaper> filterHighlights(
  List<HighlightWithPaper> all,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return [
    for (final e in all)
      if (e.highlight.quote.toLowerCase().contains(q) ||
          (e.highlight.comment ?? '').toLowerCase().contains(q) ||
          e.paper.title.toLowerCase().contains(q))
        e,
  ];
}

/// Everything you've highlighted, across papers — for reviewing what you
/// read, without opening each paper.
class AllHighlightsScreen extends ConsumerStatefulWidget {
  const AllHighlightsScreen({super.key});

  @override
  ConsumerState<AllHighlightsScreen> createState() =>
      _AllHighlightsScreenState();
}

class _AllHighlightsScreenState extends ConsumerState<AllHighlightsScreen> {
  String _query = '';

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

  /// Notes-like margins on a Mac: the page fills the window.
  double _side(BuildContext context) =>
      macPanePadding(MediaQuery.sizeOf(context).width);

  Widget _fill(bool mac, {required Widget child}) =>
      mac ? child : ReadableColumn(child: child);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(allHighlightsProvider).value ?? const [];
    final shown = filterHighlights(all, _query);

    final mac = isMac(context);
    final children = <Widget>[];
    // On a Mac each paper's highlights are cards flowing across the width.
    var group = <Widget>[];
    void flush() {
      if (group.isNotEmpty) children.add(_CardFlow(cards: group));
      group = <Widget>[];
    }

    String? currentPaper;
    for (final e in shown) {
      if (e.paper.id != currentPaper) {
        flush();
        currentPaper = e.paper.id;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(mac ? 0 : 20, 20, 20, 4),
            child: Text(
              e.paper.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
        );
      }
      final tile = ListTile(
        title: Text(
          e.highlight.quote,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ),
        subtitle: Text(
          [
            'p. ${e.highlight.pageNumber}',
            if ((e.highlight.comment ?? '').trim().isNotEmpty)
              e.highlight.comment!.trim(),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _open(e),
        onLongPress: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => HighlightSheet(highlightId: e.highlight.id),
        ),
      );
      (mac ? group : children).add(
        isDesktop(context)
            ? ContextMenuRegion(
                // The desktop's long-press: recolour, comment, copy, delete.
                actions: [
                  ContextMenuAction(
                    label: 'Open',
                    icon: Icons.open_in_new,
                    onSelected: () => _open(e),
                  ),
                  null,
                  ...highlightContextActions(
                    context,
                    ref,
                    e.highlight,
                    onComment: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) =>
                          HighlightSheet(highlightId: e.highlight.id),
                    ),
                  ),
                ],
                child: tile,
              )
            : tile,
      );
    }
    flush();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: false,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search your highlights',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            prefixIcon: Icon(Icons.search),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.replay),
            tooltip: 'Revisit highlights',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReviewScreen()),
            ),
          ),
        ],
      ),
      body: _fill(
        mac,
        child: all.isEmpty
            ? const EmptyState(
                icon: Icons.format_quote_outlined,
                title: 'No highlights yet',
                message:
                    'Select text in a PDF and choose Highlight; it will '
                    'collect here.',
              )
            : shown.isEmpty
            ? const Center(child: Text('No matches.'))
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  mac ? _side(context) : 0,
                  0,
                  mac ? _side(context) : 0,
                  32,
                ),
                children: children,
              ),
      ),
    );
  }
}

/// Highlight cards flowing in as many columns (at least 360 pt wide) as fit.
class _CardFlow extends StatelessWidget {
  const _CardFlow({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 12.0;
      final columns = ((box.maxWidth + gap) / (360 + gap)).floor().clamp(1, 6);
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards)
            SizedBox(
              width: width,
              child: Card(margin: EdgeInsets.zero, child: card),
            ),
        ],
      );
    },
  );
}
