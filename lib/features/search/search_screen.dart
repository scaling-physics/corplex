import 'dart:async';

import '../home/adaptive.dart' show ReadableColumn;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../../theme/motion_widgets.dart';
import '../attachments/attachments_browser.dart';
import '../graph/graph_screen.dart';
import '../platform/mac_window.dart' show isDesktop;
import '../library/paper_detail_screen.dart';
import '../library/pdf_viewer_screen.dart';
import '../notes/note_editor_screen.dart';
import 'pdf_text_index.dart';
import 'search_index.dart';

/// Search across everything: notes, papers and highlighted passages.
/// Results appear as you type; tapping one opens it (a highlight opens the
/// PDF at its page).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<SearchHit>>? _results;
  Future<bool>? _indexing;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      setState(() {
        _query = text.trim();
        _results = _query.isEmpty ? null : _find(_query);
        _indexing = _query.isEmpty
            ? null
            : ref.read(pdfTextIndexProvider).incomplete;
      });
    });
  }

  Future<List<SearchHit>> _find(String query) => searchEverything(ref, query);

  Future<void> _open(SearchHit hit) async {
    final db = ref.read(databaseProvider);
    final route = switch (hit.kind) {
      SearchKind.note => MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(noteId: hit.id),
      ),
      SearchKind.paper => MaterialPageRoute<void>(
        builder: (_) => PaperDetailScreen(paperId: hit.id),
      ),
      SearchKind.highlight ||
      SearchKind.pdfText => await highlightRoute(db, hit, _query),
    };
    if (route != null && mounted) {
      await Navigator.of(context).push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: context.l10n.searchHint,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: context.l10n.searchClear,
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          if (!isDesktop(context))
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: context.l10n.searchAttachments,
              onPressed: () => showAttachmentsBrowser(context),
            ),
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: context.l10n.searchMap,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GraphScreen()),
            ),
          ),
        ],
      ),
      body: ReadableColumn(
        child: _results == null
            ? EmptyState(
                icon: Icons.search,
                title: context.l10n.searchEmptyTitle,
                message: context.l10n.searchEmptyMessage,
              )
            : FutureBuilder<List<SearchHit>>(
                future: _results,
                builder: (context, snapshot) {
                  final hits = snapshot.data;
                  if (hits == null) return const SizedBox.shrink();
                  if (hits.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off,
                      title: context.l10n.searchNoMatches,
                      message: context.l10n.searchNoMatchesHint,
                    );
                  }
                  return SearchResultsList(
                    hits: hits,
                    onTap: _open,
                    indexing: _indexing,
                  );
                },
              ),
      ),
    );
  }
}

/// Notes, papers, highlights and PDF text matching [query], each kind
/// starting the PDF indexer if papers' text isn't all indexed yet.
Future<List<SearchHit>> searchEverything(WidgetRef ref, String query) async {
  final pdf = ref.read(pdfTextIndexProvider);
  // Papers' text may not be indexed yet (or since a restart): carry on.
  pdf.kickIfIncomplete();
  final hits = await ref.read(searchIndexProvider).search(query);
  return [...hits, ...await pdf.search(query)];
}

/// A highlight (or a match in a paper's text) opens its PDF at the right
/// page — or the paper's screen when the file hasn't reached this device.
Future<Route<void>?> highlightRoute(
  AppDatabase db,
  SearchHit hit,
  String query,
) async {
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(hit.paperId!))).getSingleOrNull();
  if (paper == null) return null;
  return MaterialPageRoute<void>(
    builder: (_) => paper.pdfPath == null
        ? PaperDetailScreen(paperId: paper.id)
        : PdfViewerScreen(
            paperId: paper.id,
            pdfPath: paper.pdfPath!,
            initialPage: hit.page,
            // A match in the paper's text: show it with Find.
            initialQuery: hit.kind == SearchKind.pdfText ? query : null,
          ),
  );
}

/// Search results for [query] in place, for the Mac window's list column
/// (the toolbar's search field fills it): a note or paper opens in the
/// pane beside it ([onOpenNote] / [onOpenPaper]); a highlight or a match in
/// a paper's text opens the PDF at its page.
class SearchResultsView extends ConsumerStatefulWidget {
  const SearchResultsView({
    super.key,
    required this.query,
    required this.onOpenNote,
    required this.onOpenPaper,
  });

  final String query;
  final ValueChanged<String> onOpenNote;
  final ValueChanged<String> onOpenPaper;

  @override
  ConsumerState<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends ConsumerState<SearchResultsView> {
  late Future<List<SearchHit>> _results;
  late Future<bool> _indexing;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(SearchResultsView old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  void _search() {
    _results = searchEverything(ref, widget.query);
    _indexing = ref.read(pdfTextIndexProvider).incomplete;
  }

  Future<void> _open(SearchHit hit) async {
    switch (hit.kind) {
      case SearchKind.note:
        widget.onOpenNote(hit.id);
      case SearchKind.paper:
        widget.onOpenPaper(hit.id);
      case SearchKind.highlight || SearchKind.pdfText:
        final route = await highlightRoute(
          ref.read(databaseProvider),
          hit,
          widget.query,
        );
        if (route != null && mounted) await Navigator.of(context).push(route);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SearchHit>>(
    future: _results,
    builder: (context, snapshot) {
      final hits = snapshot.data;
      if (hits == null) return const SizedBox.shrink();
      if (hits.isEmpty) {
        return EmptyState(
          icon: Icons.search_off,
          title: context.l10n.searchNoMatches,
          message: context.l10n.searchNoMatchesHint,
        );
      }
      return SearchResultsList(
        hits: hits,
        onTap: _open,
        indexing: _indexing,
        dense: true,
      );
    },
  );
}

/// Results grouped by kind (Notes, Papers, Highlights, In papers).
class SearchResultsList extends StatelessWidget {
  const SearchResultsList({
    super.key,
    required this.hits,
    required this.onTap,
    this.indexing,
    this.dense = false,
  });

  /// Smaller rows and headings, for a Mac list column.
  final bool dense;

  final List<SearchHit> hits;
  final ValueChanged<SearchHit> onTap;

  /// Whether papers' text is still being indexed (results may be partial).
  final Future<bool>? indexing;

  static Map<SearchKind, String> _labels(AppLocalizations l10n) => {
    SearchKind.note: l10n.commonNotes,
    SearchKind.paper: l10n.searchKindPapers,
    SearchKind.highlight: l10n.searchKindHighlights,
    SearchKind.pdfText: l10n.searchKindInPapers,
  };

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final labels = _labels(context.l10n);
    for (final kind in SearchKind.values) {
      final ofKind = hits.where((h) => h.kind == kind).toList();
      if (ofKind.isEmpty) continue;
      children.add(
        Padding(
          padding: dense
              ? const EdgeInsets.fromLTRB(16, 12, 16, 2)
              : const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            labels[kind]!,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
      for (final (i, hit) in ofKind.indexed) {
        children.add(
          EntranceTransition(
            key: ValueKey('${hit.kind.name}-${hit.id}-${hit.page}'),
            index: i,
            child: _HitTile(hit: hit, dense: dense, onTap: () => onTap(hit)),
          ),
        );
      }
    }
    if (indexing != null) {
      children.add(
        FutureBuilder<bool>(
          future: indexing,
          builder: (context, snapshot) => snapshot.data == true
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    context.l10n.searchIndexing,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: children,
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap, this.dense = false});

  final SearchHit hit;
  final VoidCallback onTap;
  final bool dense;

  static Widget _marked(BuildContext context, String text, TextStyle? base) {
    final c = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          for (final part in splitMarked(text))
            TextSpan(
              text: part.text,
              style: part.match
                  ? TextStyle(
                      fontWeight: FontWeight.w700,
                      backgroundColor: c.primaryContainer,
                      color: c.onPrimaryContainer,
                    )
                  : null,
            ),
        ],
      ),
      style: base,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (hit.kind) {
      SearchKind.note => Icons.edit_note_outlined,
      SearchKind.paper => Icons.article_outlined,
      SearchKind.highlight => Icons.format_quote_outlined,
      SearchKind.pdfText => Icons.picture_as_pdf_outlined,
    };
    final title = hit.title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return ListTile(
      dense: dense,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: _marked(
        context,
        title.isEmpty ? context.l10n.commonUntitled : title,
        dense ? theme.textTheme.titleSmall : theme.textTheme.titleMedium,
      ),
      subtitle: hit.snippet.isEmpty && hit.page == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _marked(
                context,
                [
                  if (hit.page != null) context.l10n.searchPage(hit.page!),
                  if (hit.snippet.isNotEmpty) hit.snippet,
                ].join(' · '),
                (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
      onTap: onTap,
    );
  }
}
