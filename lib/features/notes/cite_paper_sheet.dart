import '../library/authors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/papers_providers.dart';

/// Searchable list of papers to cite from a note. Returns the chosen
/// paper's id, or null if dismissed.
Future<String?> showCitePaperSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CitePaperSheet(),
  );
}

class _CitePaperSheet extends ConsumerStatefulWidget {
  const _CitePaperSheet();

  @override
  ConsumerState<_CitePaperSheet> createState() => _CitePaperSheetState();
}

class _CitePaperSheetState extends ConsumerState<_CitePaperSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final papers = ref.watch(papersListProvider).value ?? const [];
    final query = _query.trim().toLowerCase();
    final shown = query.isEmpty
        ? papers
        : papers
              .where(
                (p) =>
                    p.title.toLowerCase().contains(query) ||
                    p.authors.toLowerCase().contains(query),
              )
              .toList();
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
                  hintText: 'Cite a paper',
                  leading: const Icon(Icons.format_quote),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('No papers found.'))
                    : ListView(
                        children: [
                          for (final paper in shown)
                            ListTile(
                              title: Text(
                                paper.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (paper.authors.isNotEmpty)
                                    displayAuthors(paper.authors),
                                  if (paper.year != null) '${paper.year}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(context, paper.id),
                            ),
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
