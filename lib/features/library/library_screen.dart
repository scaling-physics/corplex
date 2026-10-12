import 'authors.dart';

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../home/getting_started.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../home/adaptive.dart';
import '../home/open_card.dart';
import 'paper_cover.dart';
import 'paper_detail_screen.dart';
import '../../data/tables/papers_table.dart';
import '../projects/project_menu.dart';
import '../projects/projects_providers.dart';
import '../../theme/swipe_to_trash.dart';
import '../trash/trash_actions.dart';
import 'all_highlights_screen.dart';
import 'library_actions.dart';
import 'papers_providers.dart';
import 'reading_progress.dart';
import 'study_filter.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion_widgets.dart';

/// Picks a PDF, copies it into app storage and creates its paper record,
/// then fills in the real title/authors/year from its DOI or arXiv ID in
/// the background (the paper is usable straight away). Returns the new
/// paper's id, or null if nothing was picked. Shared by the Library's
/// "Import PDF" and the note editor's link-a-paper sheet.
Future<String?> importPaperFile(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (picked?.path == null) return null;

  final localPath = await copyIntoAppStorage(picked!.path!, 'papers');
  final title = titleFromFileName(picked.name);

  final id = const Uuid().v4();
  final db = ref.read(databaseProvider);
  await db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          id: Value(id),
          title: title,
          pdfPath: Value(localPath),
        ),
      );

  if (context.mounted) {
    unawaited(
      enrichImportedPaper(ref, context, id, localPath, importedTitle: title),
    );
  }
  return id;
}

/// Imports a PDF and opens it. Used by the home screen's "Import PDF"
/// button.
Future<void> importPaper(BuildContext context, WidgetRef ref) async {
  final id = await importPaperFile(context, ref);
  if (id == null || !context.mounted) return;
  openPaper(context, ref, id);
}

/// Searchable, auto-organized library of every paper referenced across
/// notes and citations, with quick access to each paper and its
/// attachments (PDFs, NotebookLM-style podcasts, images, links).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papersAsync = ref.watch(filteredPapersProvider);
    final searching = ref.watch(librarySearchProvider).trim().isNotEmpty;

    final statusFilter = ref.watch(libraryStatusFilterProvider);
    final projects = ref.watch(projectsListProvider).value ?? const <Project>[];
    final projectFilter = ref.watch(libraryProjectFilterProvider);
    final anyStatus = (ref.watch(papersListProvider).value ?? const []).any(
      (p) => p.readingStatus != null,
    );

    final anyStudy = ref.watch(anyStudyDetailsProvider);
    final studyActive = ref.watch(studyFilterProvider).isActive;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  hintText: 'Search papers',
                  leading: const Icon(Icons.search),
                  onChanged: (value) =>
                      ref.read(librarySearchProvider.notifier).state = value,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) => switch (v) {
                  'doi' => addPaperByIdentifier(context, ref),
                  'import' => importBibtexFile(context, ref),
                  'export' => exportLibraryBibtex(context, ref),
                  'highlights' => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AllHighlightsScreen(),
                    ),
                  ),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'highlights',
                    child: ListTile(
                      leading: Icon(Icons.format_quote_outlined),
                      title: Text('All highlights'),
                      subtitle: Text('Across every paper'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'doi',
                    child: ListTile(
                      leading: Icon(Icons.travel_explore),
                      title: Text('Add by DOI or arXiv ID'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('Import references'),
                      subtitle: Text(
                        'BibTeX, RIS or CSL JSON (Zotero, Mendeley)',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.ios_share),
                      title: Text('Export as BibTeX'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: (anyStatus || projects.isNotEmpty || anyStudy || studyActive)
              ? SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final project in projects)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onLongPress: () =>
                                showProjectMenu(context, ref, project),
                            child: ChoiceChip(
                              avatar: const Icon(
                                Icons.folder_special_outlined,
                                size: 18,
                              ),
                              label: Text(project.name),
                              selected: projectFilter == project.id,
                              onSelected: (selected) =>
                                  ref
                                      .read(
                                        libraryProjectFilterProvider.notifier,
                                      )
                                      .state = selected
                                  ? project.id
                                  : null,
                            ),
                          ),
                        ),
                      if (anyStatus)
                        for (final status in [null, ...ReadingStatus.values])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(switch (status) {
                                null => 'All',
                                ReadingStatus.toRead => 'To read',
                                ReadingStatus.reading => 'Reading',
                                ReadingStatus.done => 'Done',
                              }),
                              selected: statusFilter == status,
                              onSelected: (_) =>
                                  ref
                                          .read(
                                            libraryStatusFilterProvider
                                                .notifier,
                                          )
                                          .state =
                                      status,
                            ),
                          ),
                      if (anyStudy || studyActive)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: StudyFilterChip(),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: StateSwitcher(
            stateKey: switch (papersAsync) {
              AsyncData(value: []) => searching ? 'no-results' : 'empty',
              AsyncData() => 'list',
              AsyncError() => 'error',
              _ => 'loading',
            },
            child: papersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) =>
                  Center(child: Text('Something went wrong: $error')),
              data: (papers) {
                if (papers.isEmpty) {
                  if (!searching && ref.watch(isFreshStartProvider)) {
                    return const GettingStarted();
                  }
                  return searching
                      ? const EmptyState(
                          icon: Icons.search_off,
                          title: 'No matches',
                          message: 'Try a different title or author.',
                        )
                      : const EmptyState(
                          icon: Icons.library_books_outlined,
                          title: 'Your library is empty',
                          message: 'Tap Import PDF to add a paper, or link one from a note.',
                        );
                }
                return NewItemScope(
                  ids: [for (final p in papers) p.id],
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: papers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => ListItemMotion(
                      key: ValueKey(papers[index].id),
                      id: papers[index].id,
                      index: index,
                      child: SwipeToTrash(
                        dismissKey: ValueKey('swipe-${papers[index].id}'),
                        onTrash: () => deletePaperWithUndo(
                          ref,
                          ScaffoldMessenger.of(context),
                          papers[index].id,
                          papers[index].title,
                        ),
                        child: _PaperCard(paper: papers[index]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PaperCard extends ConsumerWidget {
  const _PaperCard({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final byline = [
      if (paper.authors.isNotEmpty) displayAuthors(paper.authors),
      if (paper.year case final year?) '$year',
    ].join(' · ');

    final selected =
        hasDetailPane(context) && ref.watch(selectedPaperProvider) == paper.id;
    return OpenCard(
      selected: selected,
      onOpenInPane: () => openPaper(context, ref, paper.id),
      pageBuilder: (_) => PaperDetailScreen(paperId: paper.id),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            PaperCover(paperId: paper.id, pdfPath: paper.pdfPath, width: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paper.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (byline.isNotEmpty || paper.rating != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (paper.rating != null) '★' * paper.rating!,
                        if (byline.isNotEmpty) byline,
                      ].join('  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                  ReadingProgressBar(paper: paper),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
