import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../library/papers_providers.dart';
import 'note_papers_providers.dart';

Future<void> showLinkPaperSheet(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LinkPaperSheet(noteId: noteId),
  );
}

class _LinkPaperSheet extends ConsumerStatefulWidget {
  const _LinkPaperSheet({required this.noteId});

  final String noteId;

  @override
  ConsumerState<_LinkPaperSheet> createState() => _LinkPaperSheetState();
}

class _LinkPaperSheetState extends ConsumerState<_LinkPaperSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final papersAsync = ref.watch(papersListProvider);
    final linkedAsync = ref.watch(linkedPapersForNoteProvider(widget.noteId));
    final linkedIds =
        linkedAsync.value?.map((p) => p.id).toSet() ?? <String>{};

    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SearchBar(
                  hintText: 'Search papers to link',
                  leading: const Icon(Icons.search),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: papersAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, _) => Center(child: Text('$error')),
                  data: (papers) {
                    final query = _query.trim().toLowerCase();
                    final filtered = query.isEmpty
                        ? papers
                        : papers
                              .where(
                                (p) =>
                                    p.title.toLowerCase().contains(query) ||
                                    p.authors.toLowerCase().contains(query),
                              )
                              .toList();
                    if (filtered.isEmpty) {
                      return const Center(child: Text('No papers found.'));
                    }
                    return ListView(
                      children: filtered.map((paper) {
                        final linked = linkedIds.contains(paper.id);
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
                          trailing: Icon(
                            linked
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                          ),
                          onTap: () => _toggleLink(paper.id, linked),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLink(String paperId, bool currentlyLinked) async {
    final db = ref.read(databaseProvider);
    if (currentlyLinked) {
      await unlinkPaperFromNote(db, noteId: widget.noteId, paperId: paperId);
    } else {
      await linkPaperToNote(db, noteId: widget.noteId, paperId: paperId);
    }
  }
}
