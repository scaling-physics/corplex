import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_screen.dart';
import '../library/papers_providers.dart';
import '../notes/notes_providers.dart';

/// True while the app holds no notes and no papers: a first launch. The
/// welcome steps show only then, and go away by themselves as soon as
/// anything exists — nothing to dismiss, nothing left behind.
final isFreshStartProvider = Provider.autoDispose<bool>((ref) {
  final notes = ref.watch(notesListProvider).value;
  final papers = ref.watch(papersListProvider).value;
  return notes != null && papers != null && notes.isEmpty && papers.isEmpty;
});

/// Three steps through the read → annotate → note → cite loop, in place of
/// a blank empty state on first launch.
class GettingStarted extends ConsumerWidget {
  const GettingStarted({super.key});

  static const _steps = [
    (
      Icons.upload_file_outlined,
      'Import a paper',
      'A PDF from Files. Its title, authors and year fill in by themselves.',
    ),
    (
      Icons.format_quote_outlined,
      'Highlight as you read',
      'Press and hold on the text, then Highlight or Quote to note.',
    ),
    (
      Icons.edit_note_outlined,
      'Write and cite',
      'In a note, type / for tools, or [@ to cite a paper.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome to Corplex', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Read, annotate, take notes and cite in one place.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: c.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              for (final (i, (icon, title, text)) in _steps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.primaryContainer.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: c.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}. $title',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              FilledButton.tonalIcon(
                onPressed: () => importPaper(context, ref),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import your first paper'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
