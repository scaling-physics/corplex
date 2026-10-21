import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database.dart';
import '../../../data/database_provider.dart';
import '../../../data/tables/papers_table.dart' show ReadingStatus;
import '../../../l10n/l10n.dart';
import '../papers_providers.dart';
import '../study_details.dart';
import 'views_model.dart';

String tableColumnTitle(AppLocalizations l10n, TableColumn c) {
  if (c is StudyColumn) return c.field.labelFor(l10n);
  return switch (c.id) {
    'authors' => l10n.viewsColAuthors,
    'year' => l10n.viewsColYear,
    'venue' => l10n.viewsColVenue,
    'status' => l10n.viewsColStatus,
    'rating' => l10n.viewsColRating,
    _ => l10n.viewsColTitle,
  };
}

double _width(TableColumn c) {
  if (c is StudyColumn) return c.field == StudyField.sampleSize ? 90 : 170;
  return switch (c.id) {
    'authors' => 200,
    'year' => 70,
    'venue' => 180,
    'status' => 110,
    'rating' => 120,
    _ => 280,
  };
}

const _rowHeight = 38.0;

/// The Library as a dense, sortable table: click a header to sort, a row to
/// open the paper, Status and Rating edit in place. The title column stays
/// put while the rest scrolls sideways. ↑/↓ select, Return opens.
class PapersTable extends ConsumerStatefulWidget {
  const PapersTable({super.key, required this.papers, required this.onOpen});

  final List<Paper> papers;
  final void Function(Paper paper) onOpen;

  @override
  ConsumerState<PapersTable> createState() => _PapersTableState();
}

class _PapersTableState extends ConsumerState<PapersTable> {
  TableColumn _sort = BaseColumn.title;
  bool _ascending = true;
  final _study = <StudyField>{};
  int? _selected;
  final _hover = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  List<TableColumn> get _columns => [
    for (final c in BaseColumn.all.skip(1)) c,
    for (final f in StudyField.values)
      if (_study.contains(f)) StudyColumn(f),
  ];

  void _sortBy(TableColumn c) => setState(() {
    if (_sort.id == c.id) {
      _ascending = !_ascending;
    } else {
      _sort = c;
      _ascending = true;
    }
  });

  KeyEventResult _key(KeyEvent e, List<Paper> rows) {
    if (e is KeyUpEvent || rows.isEmpty) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(
        () => _selected = ((_selected ?? -1) + 1).clamp(0, rows.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected = ((_selected ?? rows.length) - 1).clamp(
          0,
          rows.length - 1,
        ),
      );
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter) &&
        _selected != null &&
        _selected! < rows.length) {
      widget.onOpen(rows[_selected!]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _copy(bool csv, List<Paper> rows) {
    final l10n = context.l10n;
    final cols = [BaseColumn.title, ..._columns];
    final headers = [for (final c in cols) tableColumnTitle(l10n, c)];
    final text = csv
        ? papersToCsv(rows, cols, headers)
        : papersToMarkdown(rows, cols, headers);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.viewsCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final rows = sortPapers(widget.papers, _sort, ascending: _ascending);
    if (_selected != null && _selected! >= rows.length) _selected = null;
    final offered = offeredStudyColumns(widget.papers);
    final cols = _columns;
    final rightWidth = cols.fold<double>(0, (s, col) => s + _width(col));

    Widget header(TableColumn col) => InkWell(
      key: ValueKey('table-header-${col.id}'),
      onTap: () => _sortBy(col),
      child: SizedBox(
        width: _width(col),
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  tableColumnTitle(l10n, col),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _sort.id == col.id ? c.primary : c.onSurfaceVariant,
                  ),
                ),
              ),
              if (_sort.id == col.id)
                Icon(
                  _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                  color: c.primary,
                ),
            ],
          ),
        ),
      ),
    );

    Widget rowShell(int i, Widget child, {required VoidCallback onTap}) =>
        ValueListenableBuilder<int?>(
          valueListenable: _hover,
          builder: (context, hover, _) => MouseRegion(
            onEnter: (_) => _hover.value = i,
            onExit: (_) {
              if (_hover.value == i) _hover.value = null;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _selected = i);
                onTap();
              },
              child: Container(
                height: _rowHeight,
                color: _selected == i
                    ? c.primaryContainer.withValues(alpha: 0.5)
                    : hover == i
                    ? c.onSurface.withValues(alpha: 0.05)
                    : null,
                child: child,
              ),
            ),
          ),
        );

    final titleCol = SizedBox(
      width: _width(BaseColumn.title),
      child: Column(
        children: [
          header(BaseColumn.title),
          for (final (i, p) in rows.indexed)
            rowShell(
              i,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    p.title,
                    key: ValueKey('table-title-${p.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              onTap: () => widget.onOpen(p),
            ),
        ],
      ),
    );

    final rest = SizedBox(
      width: rightWidth,
      child: Column(
        children: [
          Row(children: [for (final col in cols) header(col)]),
          for (final (i, p) in rows.indexed)
            rowShell(
              i,
              Row(
                children: [
                  for (final col in cols)
                    SizedBox(
                      width: _width(col),
                      child: _Cell(paper: p, column: col),
                    ),
                ],
              ),
              onTap: () => widget.onOpen(p),
            ),
        ],
      ),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) => _key(e, rows),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: offered.isEmpty
                      ? const SizedBox.shrink()
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final f in offered)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    key: ValueKey('table-pick-${f.key}'),
                                    label: Text(f.labelFor(l10n)),
                                    selected: _study.contains(f),
                                    onSelected: (on) => setState(
                                      () =>
                                          on ? _study.add(f) : _study.remove(f),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('table-menu'),
                  tooltip: l10n.commonMore,
                  onSelected: (v) => _copy(v == 'csv', rows),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'md',
                      child: Text(l10n.viewsCopyMarkdown),
                    ),
                    PopupMenuItem(value: 'csv', child: Text(l10n.viewsCopyCsv)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 96),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(color: c.surface, child: titleCol),
                  Container(width: 1, color: c.outlineVariant),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: rest,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends ConsumerWidget {
  const _Cell({required this.paper, required this.column});

  final Paper paper;
  final TableColumn column;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final l10n = context.l10n;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: c.onSurfaceVariant,
    );
    final pad = const EdgeInsets.symmetric(horizontal: 10);
    if (column.id == 'status') {
      final s = paper.readingStatus;
      return PopupMenuButton<ReadingStatus?>(
        key: ValueKey('table-status-${paper.id}'),
        tooltip: '',
        onSelected: (v) =>
            setReadingStatus(ref.read(databaseProvider), paper.id, v),
        itemBuilder: (_) => [
          for (final v in ReadingStatus.values)
            PopupMenuItem(value: v, child: Text(readingStatusLabel(l10n, v))),
          if (s != null)
            PopupMenuItem(value: null, child: Text(l10n.viewsNoStatus)),
        ],
        child: Padding(
          padding: pad,
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 7,
                color: switch (s) {
                  ReadingStatus.done => c.primary,
                  ReadingStatus.reading => c.primary.withValues(alpha: 0.5),
                  _ => c.outlineVariant,
                },
              ),
              const SizedBox(width: 6),
              Text(s == null ? '' : readingStatusLabel(l10n, s), style: muted),
            ],
          ),
        ),
      );
    }
    if (column.id == 'rating') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            for (var n = 1; n <= 5; n++)
              InkResponse(
                key: ValueKey('table-star-${paper.id}-$n'),
                radius: 12,
                onTap: () => setRating(
                  ref.read(databaseProvider),
                  paper.id,
                  paper.rating == n ? null : n,
                ),
                child: Icon(
                  (paper.rating ?? 0) >= n ? Icons.star : Icons.star_border,
                  size: 16,
                  color: (paper.rating ?? 0) >= n
                      ? c.primary
                      : c.outlineVariant,
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: pad,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          cellText(paper, column),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: muted,
        ),
      ),
    );
  }
}
