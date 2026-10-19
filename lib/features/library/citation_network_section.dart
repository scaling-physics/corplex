import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../home/adaptive.dart' show openPaper;
import 'metadata_lookup.dart';
import 'openalex.dart';
import 'papers_providers.dart';

/// Which library paper (if any) matches a listed work: same DOI, or the
/// same title with a compatible year.
class LibraryMatcher {
  LibraryMatcher(Iterable<Paper> papers) {
    for (final p in papers) {
      final doi = normalizeCitationDoi(p.doi);
      if (doi != null) _byDoi[doi] = p;
      final t = _title(p.title);
      if (t.isNotEmpty) _byTitle[t] = p;
    }
  }

  final _byDoi = <String, Paper>{};
  final _byTitle = <String, Paper>{};

  static String _title(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  Paper? find(OpenAlexWork w) {
    final byDoi = w.doi == null ? null : _byDoi[w.doi];
    if (byDoi != null) return byDoi;
    final p = _byTitle[_title(w.title)];
    if (p == null) return null;
    final years = {p.year, w.year}..remove(null);
    return years.length <= 1 ? p : null;
  }
}

/// A quiet "References · Cited by" row on the paper screen. Closed, it
/// costs nothing: OpenAlex is asked only once the row is opened.
class CitationNetworkSection extends ConsumerStatefulWidget {
  const CitationNetworkSection({super.key, required this.doi});

  final String doi;

  @override
  ConsumerState<CitationNetworkSection> createState() =>
      _CitationNetworkSectionState();
}

class _CitationNetworkSectionState
    extends ConsumerState<CitationNetworkSection> {
  var _open = false;
  var _cited = false; // false: References tab
  var _loading = false;
  var _loadingMore = false;
  var _unreachable = false;
  var _notFound = false;
  CitationRecord? _record;
  String? _loadedFor;

  Future<void> _load({bool refresh = false}) async {
    final doi = widget.doi;
    setState(() {
      _loading = true;
      _unreachable = false;
      _notFound = false;
    });
    try {
      final record = await ref
          .read(citationNetworkProvider)
          .load(doi, refresh: refresh);
      if (!mounted || doi != widget.doi) return;
      setState(() {
        _record = record;
        _notFound = record == null;
        _loadedFor = doi;
      });
    } on LookupFailed {
      if (mounted) setState(() => _unreachable = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    final record = _record;
    if (record == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ref
          .read(citationNetworkProvider)
          .loadMoreCited(record);
      if (mounted) setState(() => _record = next);
    } on LookupFailed {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.libraryCitationsLoadMoreFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && _loadedFor != widget.doi && !_loading) _load();
  }

  Future<void> _add(OpenAlexWork w) async {
    final db = ref.read(databaseProvider);
    final result = await addPaperFromMetadata(
      db,
      w.toMetadata(),
      id: const Uuid().v4(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.existing != null
                ? context.l10n.libraryAlreadyInLibrary
                : context.l10n.libraryCitationsAdded,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final papers = ref.watch(papersListProvider).value ?? const <Paper>[];
    final matcher = LibraryMatcher(papers);
    final reduced = AppMotion.reduced(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: AppMotion.of(context, AppMotion.medium),
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                key: const ValueKey('citation-network-toggle'),
                title: Text(context.l10n.libraryCitationsTitle),
                trailing: AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: reduced ? Duration.zero : AppMotion.short,
                  child: const Icon(Icons.expand_more),
                ),
                onTap: _toggle,
              ),
              if (_open) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text(
                                _label(context.l10n.libraryCitationsReferences, false),
                              ),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text(
                                _label(context.l10n.libraryCitationsCitedBy, true),
                              ),
                            ),
                          ],
                          selected: {_cited},
                          onSelectionChanged: (s) =>
                              setState(() => _cited = s.first),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.libraryCitationsRefresh,
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: _loading ? null : () => _load(refresh: true),
                      ),
                    ],
                  ),
                ),
                _body(theme, matcher),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _label(String name, bool cited) {
    final r = _record;
    if (r == null) return name;
    final n = cited ? r.citedTotal : r.referenceCount;
    return n > 0 ? '$name $n' : name;
  }

  Widget _message(ThemeData theme, String text, {bool retry = false}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (retry)
              TextButton(
                onPressed: _load,
                child: Text(context.l10n.libraryCitationsRetry),
              ),
          ],
        ),
      );

  Widget _body(ThemeData theme, LibraryMatcher matcher) {
    if (_loading && _record == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_unreachable && _record == null) {
      return _message(theme, context.l10n.libraryCitationsUnreachable, retry: true);
    }
    if (_unreachable) {
      return _message(theme, context.l10n.libraryCitationsRefreshFailed, retry: true);
    }
    final r = _record;
    if (_notFound || r == null) {
      return _message(theme, context.l10n.libraryCitationsNotFound);
    }
    final items = _cited ? r.cited : r.references;
    if (items.isEmpty) {
      return _message(
        theme,
        _cited
            ? context.l10n.libraryCitationsNoCiting
            : context.l10n.libraryCitationsNoReferences,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in items) _row(theme, w, matcher.find(w)),
        if (!_cited && r.referenceCount > r.references.length)
          _message(
            theme,
            context.l10n.libraryCitationsMoreNotShown(
              r.referenceCount - r.references.length,
            ),
          ),
        if (_cited && r.hasMoreCited)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(
              onPressed: _loadingMore ? null : _more,
              child: Text(
                _loadingMore
                    ? context.l10n.libraryCitationsLoading
                    : context.l10n.libraryCitationsLoadMore,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(ThemeData theme, OpenAlexWork w, Paper? inLibrary) {
    final sub = [
      if (w.authorsLine.isNotEmpty) w.authorsLine,
      if (w.year != null) '${w.year}',
      if (w.venue != null) w.venue!,
    ].join(' · ');
    return ListTile(
      key: ValueKey('cite-${w.id}'),
      title: Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: sub.isEmpty
          ? null
          : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: inLibrary != null
          ? Icon(
              Icons.check_circle_outline,
              size: 20,
              color: theme.colorScheme.primary,
              semanticLabel: context.l10n.libraryCitationsInLibrary,
            )
          : TextButton(
              onPressed: () => _add(w),
              child: Text(context.l10n.commonAdd),
            ),
      onTap: inLibrary == null
          ? null
          : () => openPaper(context, ref, inLibrary.id),
    );
  }
}
