import 'package:drift/drift.dart' show OrderingTerm, innerJoin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/papers_table.dart' show ReadingStatus;
import '../../theme/app_theme.dart';
import '../../theme/motion_widgets.dart';
import '../graph/graph_screen.dart';
import '../home/adaptive.dart' show ReadableColumn;
import '../library/authors.dart' show displayAuthors;
import '../library/paper_cover.dart';
import 'chapters.dart';
import 'chapters_section.dart';
import 'matrix_screen.dart';
import 'open_from_page.dart';
import 'project_bibliography.dart';
import 'project_menu.dart';

final projectByIdProvider = StreamProvider.autoDispose.family<Project?, String>(
  (ref, id) {
    final db = ref.watch(databaseProvider);
    return (db.select(
      db.projects,
    )..where((p) => p.id.equals(id))).watchSingleOrNull();
  },
);

/// A project's papers, alphabetically.
final projectPapersProvider = StreamProvider.autoDispose
    .family<List<Paper>, String>((ref, id) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.papers).join([
              innerJoin(
                db.projectPapers,
                db.projectPapers.paperId.equalsExp(db.papers.id),
              ),
            ])
            ..where(db.projectPapers.projectId.equals(id))
            ..orderBy([OrderingTerm.asc(db.papers.title)]);
      return query.watch().map(
        (rows) => [for (final r in rows) r.readTable(db.papers)],
      );
    });

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// Papers in [papers] marked done, as a 0..1 share (0 when there are none).
double readingProgress(List<Paper> papers) => papers.isEmpty
    ? 0
    : papers.where((p) => p.readingStatus == ReadingStatus.done).length /
          papers.length;

/// One project on a page of its own: how far along the reading is, its
/// papers and notes, and the things you can do with them as a set. Opened
/// from the project chip's long-press menu.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final project = ref.watch(projectByIdProvider(projectId)).value;
    final papers =
        ref.watch(projectPapersProvider(projectId)).value ?? const [];
    final chapters =
        ref.watch(projectChaptersProvider(projectId)).value ?? const [];
    final notes = chapters;

    if (project == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }

    final done = papers.where((p) => p.readingStatus == ReadingStatus.done);
    final children = <Widget>[
      InkWell(
        onTap: () =>
            renameProjectDialog(context, ref.read(databaseProvider), project),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(project.name, style: theme.textTheme.headlineSmall),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          [
            _count(papers.length, 'paper'),
            _count(notes.length, 'note'),
          ].join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      ChapterHeader(project: project, chapters: chapters),
      if (papers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _Progress(
            key: const ValueKey('project-progress'),
            value: readingProgress(papers),
            label: '${done.length} of ${papers.length} read',
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (papers.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Synthesis matrix'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MatrixScreen(project: project),
                  ),
                ),
              ),
            if (papers.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.list_alt, size: 18),
                label: const Text('Bibliography'),
                onPressed: () =>
                    shareProjectBibliography(context, ref, project),
              ),
            if (notes.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.ios_share, size: 18),
                label: const Text('Export project'),
                onPressed: () =>
                    exportProject(context, ref.read(databaseProvider), project),
              ),
            if (notes.isNotEmpty && project.dueDate == null)
              ActionChip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                label: const Text('Set due date'),
                onPressed: () => pickProjectDueDate(
                  context,
                  ref.read(databaseProvider),
                  project,
                ),
              ),
            if (papers.isNotEmpty || notes.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.hub_outlined, size: 18),
                label: const Text('Map'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        GraphScreen(projectId: project.id, title: project.name),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (papers.isNotEmpty) ...[
        _Heading('Papers'),
        for (final (i, p) in papers.indexed)
          EntranceTransition(
            key: ValueKey('paper-${p.id}'),
            index: i,
            child: _PaperTile(
              paper: p,
              onTap: () => openPaperFromPage(context, ref, p.id),
            ),
          ),
      ],
      ChaptersSection(project: project, chapters: chapters),
      if (papers.isEmpty && notes.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 48),
          child: EmptyState(
            icon: Icons.folder_open_outlined,
            title: 'Nothing here yet',
            message:
                'Use “Add to project” on a paper or a note to '
                'collect it here.',
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(),
      body: ReadableColumn(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: children,
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({super.key, required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: value),
          duration: AppMotion.of(context, AppMotion.long),
          curve: AppMotion.enter,
          builder: (context, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: v, minHeight: 6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String? _statusLabel(ReadingStatus? s) => switch (s) {
  ReadingStatus.toRead => 'To read',
  ReadingStatus.reading => 'Reading',
  ReadingStatus.done => 'Read',
  null => null,
};

class _PaperTile extends StatelessWidget {
  const _PaperTile({required this.paper, required this.onTap});

  final Paper paper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _statusLabel(paper.readingStatus);
    final authors = displayAuthors(paper.authors);
    final sub = [
      if (authors.isNotEmpty) authors,
      if (paper.year != null) '${paper.year}',
      ?status,
    ].join(' · ');
    return ListTile(
      leading: PaperCover(paperId: paper.id, pdfPath: paper.pdfPath, width: 40),
      title: Text(paper.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: sub.isEmpty
          ? null
          : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
