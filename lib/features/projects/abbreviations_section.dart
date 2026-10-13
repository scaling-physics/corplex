import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/adaptive.dart';
import 'abbreviations.dart';
import 'todos.dart' show openNoteAtSelection;

/// "Abbreviations · 14 defined · 3 to check": abbreviations used in a chapter
/// before it spells them out, grouped by chapter (tap to land on the use),
/// and a collapsed "Never spelled out" list. A "List" action shows the
/// alphabetical table for the front matter. Nothing at all while the project
/// has no definitions and no issues.
class ProjectAbbreviationsSection extends ConsumerWidget {
  const ProjectAbbreviationsSection({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(abbreviationsProvider(projectId)).value;
    if (report == null || report.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final issues = report.issueCount;
    final summary = [
      if (report.defined.isNotEmpty) '${report.defined.length} defined',
      if (issues > 0) '$issues to check',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Abbreviations',
                    style: theme.textTheme.titleSmall,
                    children: [
                      TextSpan(
                        text: '  $summary',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (report.defined.isNotEmpty)
                TextButton(
                  onPressed: () => _showList(context, report),
                  child: const Text('List'),
                ),
            ],
          ),
        ),
        for (final c in report.chapters) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              c.title.trim().isEmpty ? 'Untitled' : c.title.trim(),
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
          ),
          for (final i in c.issues)
            ListTile(
              key: ValueKey('abbr-${c.noteId}-${i.offset}'),
              dense: true,
              leading: Icon(Icons.abc, size: 20, color: muted),
              title: Text(i.message),
              onTap: () =>
                  openNoteAtSelection(context, ref, c.noteId, i.selection),
            ),
        ],
        if (report.undefined.isNotEmpty)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('abbr-never'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 20),
              shape: const Border(),
              collapsedShape: const Border(),
              dense: true,
              title: Text(
                'Never spelled out (${report.undefined.length})',
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
              children: [
                for (final u in report.undefined)
                  ListTile(
                    key: ValueKey('abbr-undefined-${u.token}'),
                    dense: true,
                    title: Text(u.token),
                    trailing: Text(
                      '${u.count}×',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    onTap: () => openNoteAtSelection(
                      context,
                      ref,
                      u.noteId,
                      u.selection,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _showList(BuildContext context, AbbreviationReport report) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AbbreviationList(list: report.defined),
    );
  }
}

class _AbbreviationList extends StatelessWidget {
  const _AbbreviationList({required this.list});

  final List<DefinedAbbreviation> list;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'List of abbreviations',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _copy(context, abbreviationsTsv(list)),
                    child: const Text('Copy as text'),
                  ),
                  FilledButton.tonal(
                    onPressed: () =>
                        _copy(context, abbreviationsMarkdown(list)),
                    child: const Text('Copy'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ReadableColumn(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    for (final d in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 92,
                              child: Text(
                                d.sf,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(child: Text(d.longForm)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
