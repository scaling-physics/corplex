import 'authors.dart';

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../home/getting_started.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../home/adaptive.dart';
import '../home/open_card.dart';
import 'paper_cover.dart';
import 'retraction_notice.dart';
import 'paper_detail_screen.dart';
import '../../data/tables/papers_table.dart';
import '../projects/project_menu.dart';
import '../projects/projects_providers.dart';
import '../../theme/context_menu.dart';
import '../../theme/mac_list_row.dart';
import '../../theme/swipe_to_trash.dart';
import '../platform/mac_window.dart';
import '../projects/project_picker_sheet.dart';
import 'citation_formatter.dart';
import 'pdf_viewer_screen.dart';
import '../zotero/zotero_dialog.dart';

import 'package:flutter/services.dart';

import '../trash/trash_actions.dart';
import 'all_highlights_screen.dart';
import 'library_actions.dart';
import 'papers_providers.dart';
import 'reading_progress.dart';
import 'study_filter.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion_widgets.dart';

/// Picks a PDF, copies it into app storage and creates its paper record,
/// then fills in the real title/authors/year from its DOI or arXiv ID in
/// the background (the paper is usable straight away). Returns the new
/// paper's id, or null if nothing was picked. Shared by the Library's
/// "Import PDF" and the note editor's link-a-paper sheet.
Future<String?> importPaperFile(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (picked?.path == null || !context.mounted) return null;
  return importPdfAt(context, ref, picked!.path!, picked.name);
}

/// Adds the PDF at [sourcePath] (named [name]) to the library as a paper,
/// copied into app storage, with the usual background DOI/arXiv lookup.
/// Returns the paper's id. Used by the file picker and by files pasted or
/// dropped into a note.
Future<String> importPdfAt(
  BuildContext context,
  WidgetRef ref,
  String sourcePath,
  String name,
) async {
  final localPath = await copyIntoAppStorage(sourcePath, 'papers');
  final title = titleFromFileName(name);

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

  if (context.mounted) {
    unawaited(
      enrichImportedPaper(ref, context, id, localPath, importedTitle: title),
    );
  }
  return id;
}

/// Imports a PDF and opens it. Used by the home screen's "Import PDF"
/// button.
Future<void> importPaper(BuildContext context, WidgetRef ref) async {
  final id = await importPaperFile(context, ref);
  if (id == null || !context.mounted) return;
  openPaper(context, ref, id);
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

    final statusFilter = ref.watch(libraryStatusFilterProvider);
    final projects = ref.watch(projectsListProvider).value ?? const <Project>[];
    final projectFilter = ref.watch(libraryProjectFilterProvider);
    final anyStatus = (ref.watch(papersListProvider).value ?? const []).any(
      (p) => p.readingStatus != null,
    );

    final anyStudy = ref.watch(anyStudyDetailsProvider);
    final studyActive = ref.watch(studyFilterProvider).isActive;

    return _TrashKey(
      child: Column(
        children: [
          // On a Mac the toolbar row has the search field and this menu.
          if (!isMac(context))
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                4,
                isDesktop(context) ? 8 : 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SearchBar(
                      hintText: 'Search papers',
                      leading: const Icon(Icons.search),
                      onChanged: (value) =>
                          ref.read(librarySearchProvider.notifier).state =
                              value,
                    ),
                  ),
                  const LibraryMenuButton(),
                ],
              ),
            ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: (anyStatus || projects.isNotEmpty || anyStudy || studyActive)
                ? SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final project in projects)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onLongPress: () =>
                                  showProjectMenu(context, ref, project),
                              // The desktop counterpart of the long-press.
                              onSecondaryTap: isDesktop(context)
                                  ? () => showProjectMenu(context, ref, project)
                                  : null,
                              child: ChoiceChip(
                                avatar: const Icon(
                                  Icons.folder_special_outlined,
                                  size: 18,
                                ),
                                label: Text(project.name),
                                selected: projectFilter == project.id,
                                onSelected: (selected) =>
                                    ref
                                        .read(
                                          libraryProjectFilterProvider.notifier,
                                        )
                                        .state = selected
                                    ? project.id
                                    : null,
                              ),
                            ),
                          ),
                        if (anyStatus)
                          for (final status in [null, ...ReadingStatus.values])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: Text(switch (status) {
                                  null => 'All',
                                  ReadingStatus.toRead => 'To read',
                                  ReadingStatus.reading => 'Reading',
                                  ReadingStatus.done => 'Done',
                                }),
                                selected: statusFilter == status,
                                onSelected: (_) =>
                                    ref
                                            .read(
                                              libraryStatusFilterProvider
                                                  .notifier,
                                            )
                                            .state =
                                        status,
                              ),
                            ),
                        if (anyStudy || studyActive)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: StudyFilterChip(),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
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
                    if (!searching && ref.watch(isFreshStartProvider)) {
                      return const GettingStarted();
                    }
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
                  if (isMac(context)) return _MacPaperList(papers: papers);
                  return NewItemScope(
                    ids: [for (final p in papers) p.id],
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: papers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => ListItemMotion(
                        key: ValueKey(papers[index].id),
                        id: papers[index].id,
                        index: index,
                        child: SwipeToTrash(
                          dismissKey: ValueKey('swipe-${papers[index].id}'),
                          onTrash: () => deletePaperWithUndo(
                            ref,
                            ScaffoldMessenger.of(context),
                            papers[index].id,
                            papers[index].title,
                          ),
                          child: _PaperCard(paper: papers[index]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Moves a paper to the trash with the usual Undo snackbar.
void _trashPaper(BuildContext context, WidgetRef ref, Paper paper) {
  final messenger = ScaffoldMessenger.of(context);
  if (ref.read(selectedPaperProvider) == paper.id) {
    ref.read(selectedPaperProvider.notifier).state = null;
  }
  deletePaperWithUndo(ref, messenger, paper.id, paper.title);
}

/// The right-click menu of a paper (desktop).
List<ContextMenuAction?> paperContextActions(
  BuildContext context,
  WidgetRef ref,
  Paper paper,
) => [
  ContextMenuAction(
    label: 'Open',
    icon: Icons.open_in_new,
    onSelected: () => openPaper(context, ref, paper.id),
  ),
  if (paper.pdfPath != null)
    ContextMenuAction(
      label: 'Open PDF',
      icon: Icons.picture_as_pdf_outlined,
      onSelected: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerScreen(
            paperId: paper.id,
            pdfPath: paper.pdfPath!,
            initialPage: paper.lastPage,
          ),
        ),
      ),
    ),
  ContextMenuAction(
    label: 'Add to project…',
    icon: Icons.folder_special_outlined,
    onSelected: () => showProjectPickerSheet(context, paperId: paper.id),
  ),
  ContextMenuAction(
    label: 'Copy citation',
    icon: Icons.copy_outlined,
    onSelected: () {
      Clipboard.setData(
        ClipboardData(text: formatCitation(paper, CitationStyle.apa)),
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Citation copied')));
    },
  ),
  null,
  ContextMenuAction(
    label: 'Move to trash',
    icon: Icons.delete_outline,
    destructive: true,
    onSelected: () => _trashPaper(context, ref, paper),
  ),
];

/// ⌘⌫ on a Mac moves the paper open in the detail pane to the trash, unless
/// the keyboard is busy typing (a text field, the note editor) or this tab
/// isn't the one showing.
class _TrashKey extends ConsumerStatefulWidget {
  const _TrashKey({required this.child});

  final Widget child;

  @override
  ConsumerState<_TrashKey> createState() => _TrashKeyState();
}

class _TrashKeyState extends ConsumerState<_TrashKey> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _typing() {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return false;
    var typing = false;
    void check(Element e) {
      final name = e.widget.runtimeType.toString();
      if (name == 'EditableText' || name.contains('Editor')) typing = true;
    }

    check(focus as Element);
    focus.visitAncestorElements((e) {
      check(e);
      return !typing;
    });
    return typing;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (event.logicalKey != LogicalKeyboardKey.backspace &&
        event.logicalKey != LogicalKeyboardKey.delete) {
      return false;
    }
    if (!HardwareKeyboard.instance.isMetaPressed) return false;
    if (!isMac(context) || !TickerMode.valuesOf(context).enabled) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final id = ref.read(selectedPaperProvider);
    if (id == null || _typing()) return false;
    final paper = ref.read(paperByIdProvider(id)).value;
    if (paper == null) return false;
    _trashPaper(context, ref, paper);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PaperCard extends ConsumerWidget {
  const _PaperCard({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final byline = [
      if (paper.authors.isNotEmpty) displayAuthors(paper.authors),
      if (paper.year case final year?) '$year',
    ].join(' · ');

    final selected =
        hasDetailPane(context) && ref.watch(selectedPaperProvider) == paper.id;
    final dense = isDesktop(context);
    final card = OpenCard(
      selected: selected,
      onOpenInPane: () => openPaper(context, ref, paper.id),
      pageBuilder: (_) => PaperDetailScreen(paperId: paper.id),
      child: Padding(
        padding: EdgeInsets.all(dense ? 10 : 14),
        child: Row(
          children: [
            PaperCover(
              paperId: paper.id,
              pdfPath: paper.pdfPath,
              width: dense ? 34 : 44,
            ),
            SizedBox(width: dense ? 12 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          paper.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (paper.doi != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, top: 3),
                          child: RetractionMarker(doi: paper.doi),
                        ),
                    ],
                  ),
                  if (byline.isNotEmpty || paper.rating != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (paper.rating != null) '★' * paper.rating!,
                        if (byline.isNotEmpty) byline,
                      ].join('  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                  ReadingProgressBar(paper: paper),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!dense) return card;
    return ContextMenuRegion(
      actions: paperContextActions(context, ref, paper),
      child: card,
    );
  }
}

/// The Library on a Mac: Notes-style rows (a small cover, title, "Authors ·
/// Year") in a list that takes keyboard focus. Up/Down move the selection
/// (opening that paper in the detail pane at once); Return opens the PDF,
/// or the paper's page when it has none. Without a detail pane the
/// selection is local and Up/Down only move it.
class _MacPaperList extends ConsumerStatefulWidget {
  const _MacPaperList({required this.papers});

  final List<Paper> papers;

  @override
  ConsumerState<_MacPaperList> createState() => _MacPaperListState();
}

class _MacPaperListState extends ConsumerState<_MacPaperList> {
  final _focus = FocusNode(debugLabel: 'library list');
  final _keys = <String, GlobalKey>{};

  /// The highlighted row where there is no detail pane to hold it.
  String? _local;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String? _current(bool pane) =>
      pane ? ref.read(selectedPaperProvider) : _local;

  void _move(int delta) {
    final papers = widget.papers;
    if (papers.isEmpty) return;
    final pane = hasDetailPane(context);
    final at = papers.indexWhere((p) => p.id == _current(pane));
    final next = at < 0
        ? (delta > 0 ? 0 : papers.length - 1)
        : (at + delta).clamp(0, papers.length - 1);
    _select(papers[next], pane);
  }

  void _select(Paper paper, bool pane) {
    if (pane) {
      openPaper(context, ref, paper.id);
    } else {
      setState(() => _local = paper.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _keys[paper.id]?.currentContext;
      if (row != null && row.mounted) {
        Scrollable.ensureVisible(row, alignment: 0.5);
      }
    });
  }

  void _openCurrent() {
    final pane = hasDetailPane(context);
    final id = _current(pane);
    final paper = widget.papers.where((p) => p.id == id).firstOrNull;
    if (paper == null) return;
    if (paper.pdfPath != null) {
      _openPdf(context, paper);
    } else if (pane) {
      openPaper(context, ref, paper.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaperDetailScreen(paperId: paper.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final papers = widget.papers;
    final pane = hasDetailPane(context);
    final selectedId = pane ? ref.watch(selectedPaperProvider) : _local;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        if (HardwareKeyboard.instance.isMetaPressed) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          _move(1);
        } else if (key == LogicalKeyboardKey.arrowUp) {
          _move(-1);
        } else if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          if (event is KeyDownEvent) _openCurrent();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, _) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          itemCount: papers.length,
          itemBuilder: (context, i) {
            final paper = papers[i];
            final byline = [
              if (paper.authors.isNotEmpty) displayAuthors(paper.authors),
              if (paper.year case final year?) '$year',
            ].join(' · ');
            final status = switch (paper.readingStatus) {
              ReadingStatus.toRead => 'To read',
              ReadingStatus.reading => 'Reading',
              ReadingStatus.done => 'Done',
              null => null,
            };
            final detail = [
              if (paper.rating != null) '★' * paper.rating!,
              if (byline.isNotEmpty) byline,
              ?status,
            ].join('  ');
            return KeyedSubtree(
              key: _keys.putIfAbsent(paper.id, GlobalKey.new),
              child: ContextMenuRegion(
                actions: paperContextActions(context, ref, paper),
                child: MacListRow(
                  leading: PaperCover(
                    paperId: paper.id,
                    pdfPath: paper.pdfPath,
                    width: 28,
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                  title: Text(paper.title),
                  trailing: RetractionMarker(doi: paper.doi, size: 14),
                  subtitle: detail.isEmpty ? null : Text(detail, maxLines: 1),
                  selected: paper.id == selectedId,
                  listFocused: _focus.hasFocus,
                  showDivider: i < papers.length - 1,
                  onTap: () {
                    _focus.requestFocus();
                    _select(paper, pane);
                    // Without a pane a click opens, as a card does.
                    if (!pane) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PaperDetailScreen(paperId: paper.id),
                        ),
                      );
                    }
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

void _openPdf(BuildContext context, Paper paper) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PdfViewerScreen(
      paperId: paper.id,
      pdfPath: paper.pdfPath!,
      initialPage: paper.lastPage,
    ),
  ),
);

/// The Library's ⋯ menu: all highlights, add by identifier, import and
/// export references, Zotero. Beside the search field on phones and
/// tablets; in the list column's toolbar row on a Mac.
class LibraryMenuButton extends ConsumerWidget {
  const LibraryMenuButton({super.key, this.onShowAttachments});

  /// Adds "Show Attachments" first (the Mac list column's ⋯ menu).
  final VoidCallback? onShowAttachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: onShowAttachments == null
          ? null
          : const Icon(Icons.more_horiz, size: 19),
      onSelected: (v) => switch (v) {
        'attachments' => onShowAttachments?.call(),
        'doi' => addPaperByIdentifier(context, ref),
        'import' => importBibtexFile(context, ref),
        'export' => exportLibraryBibtex(context, ref),
        'zotero' => importFromZotero(context, ref),
        'highlights' => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AllHighlightsScreen())),
        _ => null,
      },
      itemBuilder: (_) => [
        if (onShowAttachments != null)
          const PopupMenuItem(
            value: 'attachments',
            child: ListTile(
              leading: Icon(Icons.attach_file),
              title: Text('Show Attachments'),
              trailing: Text('\u23183'),
            ),
          ),
        const PopupMenuItem(
          value: 'highlights',
          child: ListTile(
            leading: Icon(Icons.format_quote_outlined),
            title: Text('All highlights'),
            subtitle: Text('Across every paper'),
          ),
        ),
        const PopupMenuItem(
          value: 'doi',
          child: ListTile(
            leading: Icon(Icons.travel_explore),
            title: Text('Add by DOI or arXiv ID'),
          ),
        ),
        const PopupMenuItem(
          value: 'import',
          child: ListTile(
            leading: Icon(Icons.file_download_outlined),
            title: Text('Import references'),
            subtitle: Text('BibTeX, RIS or CSL JSON (Zotero, Mendeley)'),
          ),
        ),
        const PopupMenuItem(
          value: 'zotero',
          child: ListTile(
            leading: Icon(Icons.sync_alt),
            title: Text('Import from Zotero…'),
          ),
        ),
        const PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.ios_share),
            title: Text('Export as BibTeX'),
          ),
        ),
      ],
    );
  }
}
