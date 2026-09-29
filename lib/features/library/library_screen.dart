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

/// Searchable, auto-organized library of every paper referenced across
/// notes and citations, with quick access to each paper and its
/// attachments (PDFs, NotebookLM-style podcasts, images, links).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _importPaper(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked?.path == null) return;

    final localPath = await copyIntoAppStorage(picked!.path!, 'papers');
    final title = p.basenameWithoutExtension(picked.name);

    final id = const Uuid().v4();
    final db = ref.read(databaseProvider);
    await db.into(db.papers).insert(
      PapersCompanion.insert(id: Value(id), title: title, pdfPath: Value(localPath)),
    );

    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PaperDetailScreen(paperId: id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papersAsync = ref.watch(filteredPapersProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              hintText: 'Search papers',
              leading: const Icon(Icons.search),
              onChanged: (value) =>
                  ref.read(librarySearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: papersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) =>
                  Center(child: Text('Something went wrong: $error')),
              data: (papers) {
                if (papers.isEmpty) {
                  return Center(
                    child: Text(
                      'Papers you reference in notes will show up here.\nTap + to import a PDF.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: papers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final paper = papers[index];
                    return ListTile(
                      title: Text(
                        paper.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: paper.authors.isEmpty
                          ? null
                          : Text(
                              paper.authors,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PaperDetailScreen(paperId: paper.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _importPaper(context, ref),
        tooltip: 'Import PDF',
        child: const Icon(Icons.add),
      ),
    );
  }
}
