import 'dart:async';

import '../home/adaptive.dart' show ReadableColumn;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/motion_widgets.dart';
import '../library/paper_detail_screen.dart';
import '../library/pdf_viewer_screen.dart';
import '../notes/note_editor_screen.dart';
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
        _results = _query.isEmpty
            ? null
            : ref.read(searchIndexProvider).search(_query);
      });
    });
  }

  Future<void> _open(SearchHit hit) async {
    final db = ref.read(databaseProvider);
    final route = switch (hit.kind) {
      SearchKind.note => MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(noteId: hit.id),
      ),
      SearchKind.paper => MaterialPageRoute<void>(
        builder: (_) => PaperDetailScreen(paperId: hit.id),
      ),
      SearchKind.highlight => await _highlightRoute(db, hit),
    };
    if (route != null && mounted) {
      await Navigator.of(context).push(route);
    }
  }

  /// A highlight opens its PDF at the right page — or the paper's screen
  /// when the file hasn't reached this device yet.
  Future<Route<void>?> _highlightRoute(AppDatabase db, SearchHit hit) async {
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
            ),
    );
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
            hintText: 'Search notes, papers and highlights',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
          style: theme.textTheme.titleMedium,
        ),
      ),
      body: ReadableColumn(
        child: _results == null
            ? const EmptyState(
                icon: Icons.search,
                title: 'Search everything',
                message: 'Find a note, a paper, or a passage you highlighted.',
              )
            : FutureBuilder<List<SearchHit>>(
                future: _results,
                builder: (context, snapshot) {
                  final hits = snapshot.data;
                  if (hits == null) return const SizedBox.shrink();
                  if (hits.isEmpty) {
                    return const EmptyState(
                      icon: Icons.search_off,
                      title: 'No matches',
                      message: 'Try fewer or different words.',
                    );
                  }
                  return _ResultsList(hits: hits, onTap: _open);
                },
              ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.hits, required this.onTap});

  final List<SearchHit> hits;
  final ValueChanged<SearchHit> onTap;

  static const _labels = {
    SearchKind.note: 'Notes',
    SearchKind.paper: 'Papers',
    SearchKind.highlight: 'Highlights',
  };

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final kind in SearchKind.values) {
      final ofKind = hits.where((h) => h.kind == kind).toList();
      if (ofKind.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            _labels[kind]!,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
      for (final (i, hit) in ofKind.indexed) {
        children.add(
          EntranceTransition(
            key: ValueKey('${hit.kind.name}-${hit.id}'),
            index: i,
            child: _HitTile(hit: hit, onTap: () => onTap(hit)),
          ),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: children,
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

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
    };
    final title = hit.title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: _marked(
        context,
        title.isEmpty ? 'Untitled' : title,
        theme.textTheme.titleMedium,
      ),
      subtitle: hit.snippet.isEmpty && hit.page == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _marked(
                context,
                [
                  if (hit.page != null) 'p. ${hit.page}',
                  if (hit.snippet.isNotEmpty) hit.snippet,
                ].join(' · '),
                theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      onTap: onTap,
    );
  }
}
