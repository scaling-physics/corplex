import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/motion_widgets.dart';
import '../library/highlights.dart';
import 'matrix.dart';

/// A project's synthesis matrix: papers × themes. Tap a cell to write in
/// it — or pull a passage from the paper's highlights.
class MatrixScreen extends ConsumerWidget {
  const MatrixScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final columns =
        ref.watch(matrixColumnsProvider(project.id)).value ?? const [];
    final papers =
        ref.watch(projectPapersProvider(project.id)).value ?? const [];
    final cells = ref.watch(matrixCellsProvider(project.id)).value ?? const {};
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (columns.isNotEmpty && papers.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Export',
              icon: const Icon(Icons.ios_share),
              onSelected: (v) async {
                final md = matrixToMarkdown(columns, papers, cells);
                if (v == 'copy') {
                  await Clipboard.setData(ClipboardData(text: md));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Table copied as Markdown')),
                    );
                  }
                } else {
                  await SharePlus.instance.share(
                    ShareParams(text: md, subject: '${project.name} matrix'),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('Copy as Markdown')),
                PopupMenuItem(value: 'share', child: Text('Share…')),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add a theme',
            onPressed: () => _askName(context, 'New theme').then((name) {
              if (name != null) addMatrixColumn(db, project.id, name);
            }),
          ),
        ],
      ),
      body: papers.isEmpty
          ? const EmptyState(
              icon: Icons.table_chart_outlined,
              title: 'No papers in this project',
              message: 'Add papers to it from their screens, then compare them here.',
            )
          : columns.isEmpty
          ? EmptyState(
              icon: Icons.table_chart_outlined,
              title: 'Compare papers side by side',
              message:
                  'Add the themes you are comparing — method, sample, '
                  'findings — and fill in what each paper says.',
              action: FilledButton(
                onPressed: () => addDefaultMatrixColumns(db, project.id),
                child: const Text('Add method, sample, findings'),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(16),
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(200),
                  columnWidths: const {0: FixedColumnWidth(150)},
                  border: TableBorder.all(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                      ),
                      children: [
                        const _Pad(child: Text('')),
                        for (final c in columns)
                          InkWell(
                            onTap: () => _columnMenu(context, db, c),
                            child: _Pad(
                              child: Text(
                                c.name,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (final paper in papers)
                      TableRow(
                        children: [
                          _Pad(
                            child: Text(
                              paperShortLabel(paper),
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          for (final c in columns)
                            InkWell(
                              onTap: () => _editCell(
                                context,
                                db,
                                column: c,
                                paper: paper,
                                current: cells['${c.id}|${paper.id}'] ?? '',
                              ),
                              child: _Pad(
                                minHeight: 64,
                                child: Text(
                                  cells['${c.id}|${paper.id}'] ?? '',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<String?> _askName(
    BuildContext context,
    String title, {
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) =>
              Navigator.pop(context, v.trim().isEmpty ? null : v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text.trim().isEmpty ? null : controller.text,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _columnMenu(
    BuildContext context,
    AppDatabase db,
    MatrixColumn column,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename theme'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete theme and its notes'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      final name = await _askName(
        context,
        'Rename theme',
        initial: column.name,
      );
      if (name != null) await renameMatrixColumn(db, column.id, name);
    } else {
      await deleteMatrixColumn(db, column.id);
    }
  }

  Future<void> _editCell(
    BuildContext context,
    AppDatabase db, {
    required MatrixColumn column,
    required Paper paper,
    required String current,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _CellSheet(db: db, column: column, paper: paper, initial: current),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.child, this.minHeight = 0});

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: minHeight),
    child: Padding(padding: const EdgeInsets.all(10), child: child),
  );
}

class _CellSheet extends ConsumerStatefulWidget {
  const _CellSheet({
    required this.db,
    required this.column,
    required this.paper,
    required this.initial,
  });

  final AppDatabase db;
  final MatrixColumn column;
  final Paper paper;
  final String initial;

  @override
  ConsumerState<_CellSheet> createState() => _CellSheetState();
}

class _CellSheetState extends ConsumerState<_CellSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    // Saved on the way out, however the sheet is dismissed.
    setMatrixCell(
      widget.db,
      widget.column.id,
      widget.paper.id,
      _controller.text,
    );
    _controller.dispose();
    super.dispose();
  }

  void _append(String text) {
    final t = _controller.text.trim();
    _controller.text = t.isEmpty ? text : '$t\n$text';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final highlights =
        ref.watch(highlightsForPaperProvider(widget.paper.id)).value ??
        const [];
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.column.name} · ${paperShortLabel(widget.paper)}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'What does this paper say?',
                ),
              ),
              if (highlights.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('From your highlights', style: theme.textTheme.titleSmall),
                for (final h in highlights)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      h.quote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('p. ${h.pageNumber}'),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _append('“${h.quote}” (p. ${h.pageNumber})'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
