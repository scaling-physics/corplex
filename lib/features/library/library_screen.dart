import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import 'paper_detail_screen.dart';
import 'papers_providers.dart';
import '../../theme/motion_widgets.dart';

/// Picks a PDF, copies it into app storage, creates its paper record and
/// opens it. Used by the home screen's "Import PDF" button.
Future<void> importPaper(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (picked?.path == null) return;

  final localPath = await copyIntoAppStorage(picked!.path!, 'papers');
  final title = p.basenameWithoutExtension(picked.name);

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

  if (!context.mounted) return;
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PaperDetailScreen(paperId: id)));
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SearchBar(
            hintText: 'Search papers',
            leading: const Icon(Icons.search),
            onChanged: (value) =>
                ref.read(librarySearchProvider.notifier).state = value,
          ),
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
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: papers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => EntranceTransition(
                    key: ValueKey(papers[index].id),
                    index: index,
                    child: _PaperCard(paper: papers[index]),
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

class _PaperCard extends StatelessWidget {
  const _PaperCard({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final byline = [
      if (paper.authors.isNotEmpty) paper.authors,
      if (paper.year case final year?) '$year',
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PaperDetailScreen(paperId: paper.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 52,
                decoration: BoxDecoration(
                  color: c.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  paper.pdfPath != null || paper.storageKey != null
                      ? Icons.picture_as_pdf_outlined
                      : Icons.article_outlined,
                  color: c.onPrimaryContainer,
                  size: 22,
                ),
              ),
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
                    if (byline.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        byline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
