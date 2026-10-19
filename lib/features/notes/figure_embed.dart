import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';
import '../projects/figures.dart';
import 'figure_markers.dart';

/// What the editor's figure chips read to show their numbers.
///
/// Numbers inside the note come from the live document (the order of its
/// definition chips); the chapter prefix and the other chapters' figures
/// come from the database ([setContext]). The editor calls
/// [documentChanged] once per document change, and chips listen, so the
/// index is built once, not per chip per frame; listeners are told only
/// when a number could have changed.
class FigureScope extends ChangeNotifier {
  String? _chapter;
  List<FigureDef> _defs = const [];
  List<FigureEntry> _others = const [];
  String _noteId = '';

  /// Opens a definition: the editor selects it in this note, or opens the
  /// other chapter's note there.
  void Function(FigureKind kind, String label)? onOpen;

  /// The chapter prefix ("3"), null outside a project.
  String? get chapter => _chapter;

  List<FigureEntry> _local = const [];
  final _byKey = <String, FigureEntry>{};

  /// This note's figures and tables as the editor shows them, numbered.
  List<FigureEntry> get local => _local;

  void _rebuild() {
    final counts = <FigureKind, int>{};
    _local = [
      for (final d in _defs)
        FigureEntry(
          kind: d.kind,
          label: d.label,
          caption: d.caption,
          number:
              '${_chapter == null ? '' : '$_chapter.'}'
              '${counts[d.kind] = (counts[d.kind] ?? 0) + 1}',
          noteId: _noteId,
          noteTitle: '',
        ),
    ];
    _byKey.clear();
    for (final e in [..._local, ..._others]) {
      _byKey.putIfAbsent('${e.kind.tag}:${e.label}', () => e);
    }
  }

  /// The other chapters' figures and tables.
  List<FigureEntry> get others => _others;

  /// The entry for a label, this note first.
  FigureEntry? find(FigureKind kind, String label) =>
      _byKey['${kind.tag}:$label'];

  /// "Figure 3.2", or "Figure ??", in the app's language.
  String displayName(AppLocalizations l10n, FigureKind kind, String label) {
    final number = find(kind, label)?.number;
    return figureDisplayName(l10n, kind, number);
  }

  /// The note's own definitions from the live [document].
  void documentChanged(Document document) {
    final next = figureDefsIn(document.toDelta());
    final same =
        next.length == _defs.length &&
        [
          for (var i = 0; i < next.length; i++)
            next[i].kind == _defs[i].kind && next[i].label == _defs[i].label,
        ].every((b) => b);
    _defs = next;
    _rebuild();
    if (!same) notifyListeners();
  }

  /// The project's numbering for [noteId] (from the database).
  void setContext(FigureContext context, String noteId) {
    final others = [
      for (final e in context.index.entries)
        if (e.noteId != noteId) e,
    ];
    final same =
        context.chapter == _chapter &&
        noteId == _noteId &&
        others.length == _others.length &&
        [for (var i = 0; i < others.length; i++) others[i] == _others[i]]
            .every((b) => b);
    _chapter = context.chapter;
    _noteId = noteId;
    _others = others;
    _rebuild();
    if (!same) notifyListeners();
  }
}

/// Puts a [FigureScope] where the editor's chips can find it.
class FigureScopeInherited extends InheritedWidget {
  const FigureScopeInherited({
    super.key,
    required this.scope,
    required super.child,
  });

  final FigureScope scope;

  static FigureScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FigureScopeInherited>()?.scope;

  @override
  bool updateShouldNotify(FigureScopeInherited old) => scope != old.scope;
}

/// The definition chip: the bold label "Figure 3.2" before the caption.
class FigureDefEmbedBuilder extends EmbedBuilder {
  const FigureDefEmbedBuilder();

  @override
  String get key => figureDefType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => node.value.data as String;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) => _FigureChip(
    marker: embedContext.node.value.data as String,
    textStyle: embedContext.textStyle,
  );
}

/// A reference chip, "Figure 3.2". Tap to go to the figure.
class FigureRefEmbedBuilder extends EmbedBuilder {
  const FigureRefEmbedBuilder();

  @override
  String get key => figureRefType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => node.value.data as String;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) => _FigureChip(
    marker: embedContext.node.value.data as String,
    textStyle: embedContext.textStyle,
  );
}

class _FigureChip extends StatelessWidget {
  const _FigureChip({required this.marker, required this.textStyle});

  final String marker;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final scope = FigureScopeInherited.maybeOf(context);
    if (scope == null) return _chip(context, null);
    return ListenableBuilder(
      listenable: scope,
      builder: (context, _) => _chip(context, scope),
    );
  }

  Widget _chip(BuildContext context, FigureScope? scope) {
    final parsed = parseFigureMarker(marker);
    final c = Theme.of(context).colorScheme;
    if (parsed == null) return Text(marker, style: textStyle);
    final entry = scope?.find(parsed.kind, parsed.label);
    final name = figureDisplayName(context.l10n, parsed.kind, entry?.number);

    if (parsed.isDefinition) {
      return Semantics(
        label: context.l10n.notesFigureCaptionLabel(name),
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(
            '$name.',
            style: textStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: entry == null ? c.error : c.primary,
            ),
          ),
        ),
      );
    }
    final known = entry != null;
    return Semantics(
      button: known,
      label: known
          ? context.l10n.notesFigureReferenceLabel(name)
          : context.l10n.notesFigureReferenceMissing,
      child: GestureDetector(
        onTap: known
            ? () => scope?.onOpen?.call(parsed.kind, parsed.label)
            : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: known
                ? c.primaryContainer.withValues(alpha: 0.6)
                : c.errorContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            name,
            style: textStyle.copyWith(
              color: known ? c.onPrimaryContainer : c.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks which figure or table to refer to: this note's (live) and the
/// other chapters' (from the database), searchable by number or caption.
Future<FigureEntry?> showFigureRefSheet(
  BuildContext context,
  FigureScope scope,
) => showModalBottomSheet<FigureEntry>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _FigureRefSheet(scope: scope),
);

class _FigureRefSheet extends StatefulWidget {
  const _FigureRefSheet({required this.scope});

  final FigureScope scope;

  @override
  State<_FigureRefSheet> createState() => _FigureRefSheetState();
}

class _FigureRefSheetState extends State<_FigureRefSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final all = [...scope.local, ...scope.others];
    final q = _query.trim().toLowerCase();
    bool matches(FigureEntry e) =>
        q.isEmpty ||
        figureDisplayName(l10n, e.kind, e.number).toLowerCase().contains(q) ||
        scope.caption(l10n, e).toLowerCase().contains(q);
    final shown = [
      for (final e in all)
        if (matches(e)) e,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Text(l10n.notesFiguresEmpty),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l10n.notesSearchFigures,
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in shown)
                        ListTile(
                          key: ValueKey('figure-${e.kind.tag}-${e.label}'),
                          leading: Icon(
                            e.kind == FigureKind.figure
                                ? Icons.image_outlined
                                : Icons.table_chart_outlined,
                          ),
                          title: Text(
                            figureDisplayName(l10n, e.kind, e.number),
                          ),
                          subtitle: scope.caption(l10n, e).isEmpty
                              ? null
                              : Text(
                                  scope.caption(l10n, e),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: e.noteTitle.isEmpty
                              ? null
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 120,
                                  ),
                                  child: Text(
                                    e.noteTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                          onTap: () => Navigator.pop(context, e),
                        ),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l10n.notesNothingMatches),
                        ),
                    ],
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

extension on FigureScope {
  /// A caption for display: references written out, citations as typed.
  String caption(AppLocalizations l10n, FigureEntry e) => replaceFigureRefs(
    e.caption,
    (kind, label) => displayName(l10n, kind, label),
  );
}

/// "Figure 3.2" / "Abbildung 3.2" for the editor; "Figure ??" when the
/// label is unknown ([number] null). Exports keep [FigureEntry.name].
String figureDisplayName(
  AppLocalizations l10n,
  FigureKind kind,
  String? number,
) => switch ((kind, number)) {
  (FigureKind.figure, null) => l10n.notesFigureMissing,
  (FigureKind.table, null) => l10n.notesTableMissing,
  (FigureKind.figure, final n?) => l10n.notesFigureName(n),
  (FigureKind.table, final n?) => l10n.notesTableName(n),
};
