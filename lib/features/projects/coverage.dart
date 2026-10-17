import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/papers_table.dart' show ReadingStatus;
import '../../theme/app_theme.dart';
import '../library/citation_formatter.dart' show CitationStyle;
import '../library/citations.dart';
import '../lock/note_lock_service.dart';
import '../notes/note_content.dart' show decodeNoteContent;
import 'open_from_page.dart';
import 'readable_content.dart';

/// A project's chapters: its notes, in reading order. Equality is by value so
/// it can key a provider family.
class ChapterQuery {
  ChapterQuery(this.projectId, List<String> noteIds)
    : noteIds = List.unmodifiable(noteIds);

  final String projectId;
  final List<String> noteIds;

  @override
  bool operator ==(Object other) =>
      other is ChapterQuery &&
      other.projectId == projectId &&
      other.noteIds.length == noteIds.length &&
      [for (var i = 0; i < noteIds.length; i++) noteIds[i] == other.noteIds[i]]
          .every((e) => e);

  @override
  int get hashCode => Object.hash(projectId, Object.hashAll(noteIds));
}

/// A chapter's text, as stored (citations as `[@key]`).
class CoverageNote {
  const CoverageNote({
    required this.id,
    required this.title,
    required this.content,
  });
  final String id;
  final String title;
  final String content;
}

/// One chapter's citations.
class ChapterCoverage {
  const ChapterCoverage({
    required this.noteId,
    required this.title,
    required this.index,
    required this.cited,
  });
  final String noteId;
  final String title;

  /// Position among the chapters, from 0.
  final int index;

  /// Papers cited here with how many times each, most cited first.
  final List<({Paper paper, int count})> cited;

  int get total => cited.fold(0, (a, c) => a + c.count);
}

/// A paper cited somewhere, with where.
class CitedPaper {
  const CitedPaper({
    required this.paper,
    required this.inProject,
    required this.chapters,
  });
  final Paper paper;
  final bool inProject;

  /// Chapters citing it, in chapter order.
  final List<({String noteId, String title, int index, int count})> chapters;

  int get total => chapters.fold(0, (a, c) => a + c.count);
}

/// A paper that was read (or has highlights) but no chapter cites.
class UncitedPaper {
  const UncitedPaper({required this.paper, required this.highlights});
  final Paper paper;
  final int highlights;
}

class Coverage {
  const Coverage({
    required this.chapters,
    required this.cited,
    required this.readNotCited,
    required this.citedOutsideProject,
    required this.unknownKeys,
  });

  /// One entry per chapter, in order (empty `cited` when it cites nothing).
  final List<ChapterCoverage> chapters;

  /// Every paper cited at all, ordered by first chapter then title.
  final List<CitedPaper> cited;

  /// Highlights first, then title.
  final List<UncitedPaper> readNotCited;

  /// Cited papers that aren't in the project.
  final List<Paper> citedOutsideProject;

  /// Keys cited that match no library paper.
  final Set<String> unknownKeys;

  bool get isEmpty =>
      cited.isEmpty && readNotCited.isEmpty && citedOutsideProject.isEmpty;

  static const none = Coverage(
    chapters: [],
    cited: [],
    readNotCited: [],
    citedOutsideProject: [],
    unknownKeys: {},
  );
}

final _group = RegExp(r'\[@[^\]\n]+\]');

/// Citations in [text] with occurrence counts: `[@a; @b]` counts once for
/// each of a and b; a key repeated in one group counts once for it.
Map<String, int> countCitations(String text) {
  final counts = <String, int>{};
  for (final m in _group.allMatches(text)) {
    for (final key in citedKeys(m.group(0)!)) {
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  return counts;
}

/// Which papers each chapter cites, and which read papers no chapter cites.
///
/// * [chapters] in order; [papers] every library paper (matched by citekey).
/// * [projectPaperIds]: papers added to the project.
/// * [linkedPaperIds]: papers linked to the chapters (note to paper links);
///   those with highlights count as the project's too.
/// * [highlightCounts]: highlights per paper id.
///
/// "Read but not cited" are uncited papers of the project (or linked to its
/// notes) that have highlights or are being read / read. A paper merely
/// waiting in the project, untouched, isn't "read".
Coverage computeCoverage({
  required List<CoverageNote> chapters,
  required List<Paper> papers,
  required Set<String> projectPaperIds,
  Set<String> linkedPaperIds = const {},
  Map<String, int> highlightCounts = const {},
}) {
  final byKey = {
    for (final p in papers)
      if (p.citekey != null && p.citekey!.isNotEmpty) p.citekey!: p,
  };
  final byId = {for (final p in papers) p.id: p};
  final unknown = <String>{};
  final perChapter = <ChapterCoverage>[];
  final citedChapters =
      <String, List<({String noteId, String title, int index, int count})>>{};
  for (final (i, note) in chapters.indexed) {
    final text = decodeNoteContent(note.content).toPlainText();
    final rows = <({Paper paper, int count})>[];
    final merged = <String, int>{};
    for (final e in countCitations(text).entries) {
      final paper = byKey[e.key];
      if (paper == null) {
        unknown.add(e.key);
        continue;
      }
      merged[paper.id] = (merged[paper.id] ?? 0) + e.value;
    }
    for (final e in merged.entries) {
      rows.add((paper: byId[e.key]!, count: e.value));
      (citedChapters[e.key] ??= []).add((
        noteId: note.id,
        title: note.title,
        index: i,
        count: e.value,
      ));
    }
    rows.sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.paper.title.compareTo(b.paper.title);
    });
    perChapter.add(
      ChapterCoverage(
        noteId: note.id,
        title: note.title,
        index: i,
        cited: rows,
      ),
    );
  }

  final cited =
      [
        for (final e in citedChapters.entries)
          CitedPaper(
            paper: byId[e.key]!,
            inProject: projectPaperIds.contains(e.key),
            chapters: e.value,
          ),
      ]..sort((a, b) {
        final c = a.chapters.first.index.compareTo(b.chapters.first.index);
        return c != 0 ? c : a.paper.title.compareTo(b.paper.title);
      });

  final candidates = <String>{
    ...projectPaperIds,
    for (final id in linkedPaperIds)
      if ((highlightCounts[id] ?? 0) > 0) id,
  };
  final uncited = <UncitedPaper>[];
  for (final id in candidates) {
    final paper = byId[id];
    if (paper == null || citedChapters.containsKey(id)) continue;
    final n = highlightCounts[id] ?? 0;
    final read =
        n > 0 ||
        paper.readingStatus == ReadingStatus.reading ||
        paper.readingStatus == ReadingStatus.done;
    if (read) uncited.add(UncitedPaper(paper: paper, highlights: n));
  }
  uncited.sort((a, b) {
    final c = b.highlights.compareTo(a.highlights);
    return c != 0 ? c : a.paper.title.compareTo(b.paper.title);
  });

  return Coverage(
    chapters: perChapter,
    cited: cited,
    readNotCited: uncited,
    citedOutsideProject: [
      for (final c in cited)
        if (!c.inProject) c.paper,
    ],
    unknownKeys: unknown,
  );
}

/// The coverage of a project's chapters, live.
final coverageProvider = StreamProvider.autoDispose
    .family<Coverage, ChapterQuery>((ref, query) {
      final db = ref.watch(databaseProvider);
      final lock = ref.watch(noteLockServiceProvider);
      Future<Coverage> load() async {
        final ids = query.noteIds;
        final notes = await (db.select(
          db.notes,
        )..where((n) => n.id.isIn(ids))).get();
        final byId = {for (final n in notes) n.id: n};
        final projectPapers = await (db.select(
          db.projectPapers,
        )..where((r) => r.projectId.equals(query.projectId))).get();
        final links = ids.isEmpty
            ? <NotePaperRef>[]
            : await (db.select(
                db.notePaperRefs,
              )..where((r) => r.noteId.isIn(ids))).get();
        final counts = await db
            .customSelect(
              'SELECT paper_id, COUNT(*) AS n FROM highlights GROUP BY paper_id',
            )
            .get();
        final papers = await db.select(db.papers).get();
        // A locked chapter's citations are read only while it's unlocked;
        // otherwise it shows as a chapter citing nothing.
        final chapters = <CoverageNote>[];
        for (final id in ids) {
          final n = byId[id];
          if (n == null) continue;
          chapters.add(
            CoverageNote(
              id: n.id,
              title: n.title,
              content: await readableNoteContent(lock, n.id, n.content) ?? '',
            ),
          );
        }
        return computeCoverage(
          chapters: chapters,
          papers: papers,
          projectPaperIds: {for (final r in projectPapers) r.paperId},
          linkedPaperIds: {for (final r in links) r.paperId},
          highlightCounts: {
            for (final r in counts)
              r.read<String>('paper_id'): r.read<int>('n'),
          },
        );
      }

      return db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              db.notes,
              db.papers,
              db.projectPapers,
              db.highlights,
              db.notePaperRefs,
            },
          )
          .watch()
          .asyncMap((_) => load());
    });

String _who(Paper paper) =>
    inTextCitation(paper, CitationStyle.apa).replaceAll(RegExp(r'^\(|\)$'), '');

String _statusLabel(ReadingStatus? s) => switch (s) {
  ReadingStatus.toRead => 'To read',
  ReadingStatus.reading => 'Reading',
  ReadingStatus.done => 'Read',
  null => '',
};

/// Which papers the chapters cite, which read papers they don't, and a hint
/// for citations to papers outside the project. Three quiet collapsed rows
/// under one heading; nothing at all when there is nothing to say.
class ChapterCoverageSection extends ConsumerWidget {
  const ChapterCoverageSection({
    super.key,
    required this.projectId,
    required this.orderedNoteIds,
  });

  final String projectId;
  final List<String> orderedNoteIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverage = ref
        .watch(coverageProvider(ChapterQuery(projectId, orderedNoteIds)))
        .value;
    if (coverage == null || coverage.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final style = AppMotion.reduced(context)
        ? AnimationStyle.noAnimation
        : null;

    Widget group(String title, List<Widget> children, {Key? key}) =>
        ExpansionTile(
          key: key,
          title: Text(title, style: theme.textTheme.bodyMedium),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20),
          expansionAnimationStyle: style,
          children: children,
        );

    void openPaper(String id) => openPaperFromPage(context, ref, id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
          child: Text('Citations', style: theme.textTheme.titleSmall),
        ),
        if (coverage.cited.isNotEmpty)
          group('Cited in chapters (${coverage.cited.length})', [
            for (final c in coverage.cited)
              ListTile(
                key: ValueKey('cited-${c.paper.id}'),
                dense: true,
                title: Text(
                  c.paper.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Wrap(
                  spacing: 4,
                  children: [
                    Text(_who(c.paper)),
                    for (final ch in c.chapters)
                      InkWell(
                        key: ValueKey('chapter-${c.paper.id}-${ch.noteId}'),
                        onTap: () => openNoteFromPage(context, ref, ch.noteId),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Ch. ${ch.index + 1} · ${ch.count}×',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () => openPaper(c.paper.id),
              ),
          ]),
        if (coverage.readNotCited.isNotEmpty)
          group('Read but not cited (${coverage.readNotCited.length})', [
            for (final u in coverage.readNotCited)
              ListTile(
                key: ValueKey('uncited-${u.paper.id}'),
                dense: true,
                title: Text(
                  u.paper.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    _who(u.paper),
                    _statusLabel(u.paper.readingStatus),
                    if (u.highlights > 0)
                      '${u.highlights} highlight${u.highlights == 1 ? '' : 's'}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
                onTap: () => openPaper(u.paper.id),
              ),
          ]),
        if (coverage.citedOutsideProject.isNotEmpty)
          group(
            'Cited, not in this project (${coverage.citedOutsideProject.length})',
            [
              for (final p in coverage.citedOutsideProject)
                ListTile(
                  key: ValueKey('outside-${p.id}'),
                  dense: true,
                  title: Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_who(p)),
                  onTap: () => openPaper(p.id),
                ),
            ],
          ),
      ],
    );
  }
}
