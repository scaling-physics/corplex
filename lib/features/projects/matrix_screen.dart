import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/motion_widgets.dart';
import '../library/highlights.dart';
import '../library/study_details.dart';
import 'matrix.dart';
import '../platform/share_origin.dart';

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
              tooltip: context.l10n.matrixExport,
              icon: const Icon(Icons.ios_share),
              onSelected: (v) async {
                final md = matrixToMarkdown(columns, papers, cells);
                if (v == 'copy') {
                  await Clipboard.setData(ClipboardData(text: md));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.matrixCopiedAsMarkdown),
                      ),
                    );
                  }
                } else {
                  await SharePlus.instance.share(
                    ShareParams(
                      text: md,
                      subject: context.l10n.matrixShareSubject(project.name),
                      sharePositionOrigin: shareOrigin(context),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'copy',
                  child: Text(context.l10n.matrixCopyAsMarkdown),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Text(context.l10n.matrixShare),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.l10n.matrixAddTheme,
            onPressed: () => _addColumn(context, db, columns),
          ),
        ],
      ),
      body: papers.isEmpty
          ? EmptyState(
              icon: Icons.table_chart_outlined,
              title: context.l10n.matrixNoPapers,
              message: context.l10n.matrixNoPapersMessage,
            )
          : columns.isEmpty
          ? EmptyState(
              icon: Icons.table_chart_outlined,
              title: context.l10n.matrixEmptyTitle,
              message: context.l10n.matrixEmptyMessage,
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () =>
                        addDefaultMatrixColumns(db, project.id, context.l10n),
                    child: Text(context.l10n.matrixAddDefaults),
                  ),
                  TextButton(
                    onPressed: () =>
                        addStudyColumns(db, project.id, context.l10n),
                    child: Text(context.l10n.matrixAddStudyColumns),
                  ),
                ],
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
                                current: _editable(c, paper, cells),
                              ),
                              child: _Pad(
                                minHeight: 64,
                                child: Text(
                                  matrixCellText(c, paper, cells),
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

  /// The text a bound cell is edited as (`a; b` for lists).
  String _editable(MatrixColumn c, Paper paper, Map<String, String> cells) {
    final field = StudyField.byKey(c.paperField);
    return field == null
        ? cells['${c.id}|${paper.id}'] ?? ''
        : studyValue(paper, field);
  }

  Future<void> _addColumn(
    BuildContext context,
    AppDatabase db,
    List<MatrixColumn> columns,
  ) async {
    final have = {for (final c in columns) c.paperField};
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(context.l10n.matrixNewTheme),
                onTap: () => Navigator.pop(context, 'new'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(context.l10n.matrixFromStudyDetails),
              ),
              if (StudyField.values.any((f) => !have.contains(f.key)))
                ListTile(
                  leading: const Icon(Icons.table_rows_outlined),
                  title: Text(context.l10n.matrixAddStudyColumns),
                  subtitle: Text(context.l10n.matrixAllNotHereYet),
                  onTap: () => Navigator.pop(context, 'all'),
                ),
              for (final f in StudyField.values)
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(f.labelFor(context.l10n)),
                  enabled: !have.contains(f.key),
                  subtitle: have.contains(f.key)
                      ? Text(context.l10n.matrixAlreadyAColumn)
                      : null,
                  onTap: () => Navigator.pop(context, f),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'new') {
      final name = await _askName(context, context.l10n.matrixNewTheme);
      if (name != null) await addMatrixColumn(db, project.id, name);
    } else if (choice == 'all') {
      await addStudyColumns(db, project.id, context.l10n);
    } else if (choice is StudyField) {
      await addMatrixColumn(
        db,
        project.id,
        choice.labelFor(context.l10n),
        field: choice,
      );
    }
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
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text.trim().isEmpty ? null : controller.text,
            ),
            child: Text(context.l10n.commonSave),
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
              title: Text(context.l10n.matrixRenameTheme),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(
                column.paperField == null
                    ? context.l10n.matrixDeleteTheme
                    : context.l10n.matrixDeleteColumn,
              ),
              subtitle: column.paperField == null
                  ? null
                  : Text(context.l10n.matrixPapersKeepDetails),
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
        context.l10n.matrixRenameTheme,
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
    // Saved on the way out, however the sheet is dismissed. A column bound
    // to study details writes the paper itself (only if it changed).
    final field = StudyField.byKey(widget.column.paperField);
    if (field == null) {
      setMatrixCell(
        widget.db,
        widget.column.id,
        widget.paper.id,
        _controller.text,
      );
    } else if (_controller.text.trim() != widget.initial.trim()) {
      setStudyValue(widget.db, widget.paper.id, field, _controller.text);
    }
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
                decoration: InputDecoration(
                  hintText: widget.column.paperField == null
                      ? context.l10n.matrixCellHint
                      : (StudyField.byKey(widget.column.paperField)?.isList ??
                            false)
                      ? context.l10n.matrixSeparateWithSemicolon
                      : null,
                ),
              ),
              if (highlights.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  context.l10n.matrixFromHighlights,
                  style: theme.textTheme.titleSmall,
                ),
                for (final h in highlights)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      h.quote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(context.l10n.notesPageShort(h.pageNumber)),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _append(
                      '“${h.quote}” (${context.l10n.notesPageShort(h.pageNumber)})',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
