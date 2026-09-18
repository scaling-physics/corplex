import 'package:flutter/material.dart';

/// Searchable, auto-organized library of every paper referenced across
/// notes and citations, with quick access to each paper and its
/// attachments (PDFs, NotebookLM-style podcasts, images, links).
/// Placeholder until the paper/citation data model is built.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              hintText: 'Search papers',
              leading: const Icon(Icons.search),
              onTap: () {},
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Papers you reference in notes will show up here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
