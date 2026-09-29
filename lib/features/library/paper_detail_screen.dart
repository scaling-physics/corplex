import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../notes/note_editor_screen.dart';
import '../audio/audio_link.dart';
import '../audio/audio_playback.dart';
import '../audio/audio_player_bar.dart';
import 'add_attachment_sheet.dart';
import 'highlights.dart';
import '../projects/project_picker_sheet.dart';
import '../trash/trash_actions.dart';
import '../projects/projects_providers.dart';
import '../sync/sync_service.dart';
import 'metadata_lookup.dart';
import '../../data/tables/papers_table.dart';
import 'citation_formatter.dart';
import 'papers_providers.dart';
import 'pdf_viewer_screen.dart';
import 'split_reader.dart';
import '../../theme/app_theme.dart';

class PaperDetailScreen extends ConsumerStatefulWidget {
  const PaperDetailScreen({super.key, required this.paperId});

  final String paperId;

  @override
  ConsumerState<PaperDetailScreen> createState() => _PaperDetailScreenState();
}

class _PaperDetailScreenState extends ConsumerState<PaperDetailScreen> {
  final _titleController = TextEditingController();
  final _authorsController = TextEditingController();
  final _yearController = TextEditingController();
  final _venueController = TextEditingController();
  final _doiController = TextEditingController();
  bool _lookingUp = false;
  Timer? _debounce;
  bool _loaded = false;
  CitationStyle _citationStyle = CitationStyle.apa;

  @override
  void initState() {
    super.initState();
    _loadPaper();
    _titleController.addListener(_scheduleSave);
    _authorsController.addListener(_scheduleSave);
    _yearController.addListener(_scheduleSave);
    _venueController.addListener(_scheduleSave);
    _doiController.addListener(_scheduleSave);
  }

  Future<void> _loadPaper() async {
    final db = ref.read(databaseProvider);
    final paper = await (db.select(
      db.papers,
    )..where((p) => p.id.equals(widget.paperId))).getSingleOrNull();
    if (paper != null && mounted) {
      _showPaper(paper);
    }
    setState(() => _loaded = true);
  }

  /// What each field last held according to the database, so an outside
  /// change (a background lookup, a sync from another device) can update a
  /// field the reader hasn't touched without clobbering one they have.
  final _fromDb = <TextEditingController, String>{};

  Map<TextEditingController, String> _fieldValues(Paper paper) => {
    _titleController: paper.title,
    _authorsController: paper.authors,
    _yearController: paper.year?.toString() ?? '',
    _venueController: paper.venue ?? '',
    _doiController: paper.doi ?? '',
  };

  void _showPaper(Paper paper) {
    for (final entry in _fieldValues(paper).entries) {
      entry.key.text = entry.value;
      _fromDb[entry.key] = entry.value;
    }
  }

  void _absorbOutsideChanges(Paper? paper) {
    if (paper == null || !_loaded) return;
    for (final entry in _fieldValues(paper).entries) {
      final controller = entry.key;
      final untouched = controller.text == _fromDb[controller];
      if (entry.value != _fromDb[controller]) {
        _fromDb[controller] = entry.value;
        if (untouched) controller.text = entry.value;
      }
    }
  }

  Future<void> _moveToTrash() async {
    final messenger = ScaffoldMessenger.of(context);
    final title = _titleController.text;
    _debounce?.cancel();
    await _save();
    if (!mounted) return;
    Navigator.of(context).pop();
    await deletePaperWithUndo(ref, messenger, widget.paperId, title);
  }

  /// Fills empty details from the DOI or arXiv ID in the DOI field.
  Future<void> _lookUp() async {
    final id = parseIdentifier(_doiController.text);
    final messenger = ScaffoldMessenger.of(context);
    if (id == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a DOI or arXiv ID first.')),
      );
      return;
    }
    setState(() => _lookingUp = true);
    try {
      await _save();
      final meta = await ref.read(metadataLookupProvider).lookup(id);
      if (!mounted) return;
      if (meta == null) {
        messenger.showSnackBar(
          SnackBar(content: Text('No paper found for ${id.value}.')),
        );
        return;
      }
      final db = ref.read(databaseProvider);
      final changed = await fillMissingMetadata(db, widget.paperId, meta);
      final paper = await (db.select(
        db.papers,
      )..where((p) => p.id.equals(widget.paperId))).getSingle();
      if (!mounted) return;
      _showPaper(paper);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            changed
                ? 'Filled in the missing details.'
                : 'Nothing new to fill in.',
          ),
        ),
      );
    } on LookupFailed {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn\'t reach the lookup service.')),
      );
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    await (db.update(
      db.papers,
    )..where((p) => p.id.equals(widget.paperId))).write(
      PapersCompanion(
        title: Value(_titleController.text),
        authors: Value(_authorsController.text),
        year: Value(int.tryParse(_yearController.text.trim())),
        venue: Value(
          _venueController.text.trim().isEmpty
              ? null
              : _venueController.text.trim(),
        ),
        doi: Value(
          _doiController.text.trim().isEmpty
              ? null
              : _doiController.text.trim(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _authorsController.dispose();
    _yearController.dispose();
    _venueController.dispose();
    _doiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachmentsAsync = ref.watch(
      attachmentsForPaperProvider(widget.paperId),
    );
    final paperAsync = ref.watch(paperByIdProvider(widget.paperId));
    ref.listen(paperByIdProvider(widget.paperId), (_, next) {
      _absorbOutsideChanges(next.value);
    });
    final notesAsync = ref.watch(notesForPaperProvider(widget.paperId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'trash') _moveToTrash();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Move to trash'),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: AudioPlayerBar()),
      body: !_loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                TextField(
                  controller: _titleController,
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
                TextField(
                  controller: _authorsController,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Authors',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                _PdfButton(paperId: widget.paperId, paper: paperAsync.value),
                _ReadingStatusRow(paper: paperAsync.value),
                _ProjectChips(paperId: widget.paperId),
                _HighlightsSection(paper: paperAsync.value),
                _Section(
                  title: 'Attachments',
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    onPressed: () => showAddAttachmentSheet(
                      context,
                      ref,
                      paperId: widget.paperId,
                    ),
                  ),
                  child: attachmentsAsync.when(
                    loading: () => const SizedBox(height: 56),
                    error: (error, _) =>
                        Text('Could not load attachments: $error'),
                    data: (attachments) {
                      if (attachments.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Podcasts, images, links or files for this paper.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        );
                      }
                      return Column(
                        children: attachments
                            .map((a) => _AttachmentTile(attachment: a))
                            .toList(),
                      );
                    },
                  ),
                ),
                _Section(
                  title: 'Details',
                  trailing: TextButton.icon(
                    icon: _lookingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore, size: 18),
                    label: const Text('Look up'),
                    onPressed: _lookingUp ? null : _lookUp,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TextField(
                          controller: _doiController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'DOI or arXiv ID',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _venueController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Journal or conference',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _yearController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Year'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (paperAsync.value case final paper?)
                  _Section(
                    title: 'Citation',
                    trailing: IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 20),
                      tooltip: 'Copy citation',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: formatCitation(paper, _citationStyle),
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Citation copied')),
                        );
                      },
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<CitationStyle>(
                            showSelectedIcon: false,
                            segments: CitationStyle.values
                                .map(
                                  (style) => ButtonSegment(
                                    value: style,
                                    label: Text(style.label),
                                  ),
                                )
                                .toList(),
                            selected: {_citationStyle},
                            onSelectionChanged: (selected) =>
                                setState(() => _citationStyle = selected.first),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: AppMotion.medium,
                            child: SelectableText(
                              formatCitation(paper, _citationStyle),
                              key: ValueKey(_citationStyle),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (notesAsync.value case final notes? when notes.isNotEmpty)
                  _Section(
                    title: 'Referenced in notes',
                    child: Column(
                      children: notes
                          .map(
                            (note) => ListTile(
                              leading: const Icon(Icons.edit_note_outlined),
                              title: Text(
                                note.title.isEmpty ? 'Untitled' : note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      NoteEditorScreen(noteId: note.id),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// "Open PDF" when the file is on this device; "Download PDF" when it is
/// only in the cloud (Wi-Fi-only / on-demand settings, or still syncing);
/// nothing for papers without a PDF.
class _PdfButton extends ConsumerStatefulWidget {
  const _PdfButton({required this.paperId, required this.paper});

  final String paperId;
  final Paper? paper;

  @override
  ConsumerState<_PdfButton> createState() => _PdfButtonState();
}

class _PdfButtonState extends ConsumerState<_PdfButton> {
  bool _downloading = false;

  void _open(String pdfPath, int? page) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PdfViewerScreen(
        paperId: widget.paperId,
        pdfPath: pdfPath,
        initialPage: page,
      ),
    ),
  );

  Future<void> _download() async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(syncServiceProvider)
        .downloadFile(paperId: widget.paperId);
    if (!mounted) return;
    setState(() => _downloading = false);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn\'t download the PDF. Try again.')),
      );
    }
    // On success the paper row updates with its local path, which rebuilds
    // this button as "Open PDF".
  }

  @override
  Widget build(BuildContext context) {
    final paper = widget.paper;
    if (paper == null) return const SizedBox.shrink();
    if (paper.pdfPath case final pdfPath?) {
      final resume = paper.lastPage != null && paper.lastPage! > 1;
      final open = FilledButton.tonalIcon(
        icon: const Icon(Icons.menu_book_outlined),
        label: Text(
          resume ? 'Continue reading · p. ${paper.lastPage}' : 'Open PDF',
        ),
        onPressed: () => _open(pdfPath, paper.lastPage),
      );
      // Only where there's room for two panes; nothing extra on a phone.
      if (!canSplit(context)) return open;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          open,
          OutlinedButton.icon(
            icon: const Icon(Icons.vertical_split_outlined),
            label: const Text('Read with a note'),
            onPressed: () => openSplitReader(context, ref, paper),
          ),
        ],
      );
    }
    if (paper.storageKey != null) {
      return FilledButton.tonalIcon(
        icon: _downloading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_download_outlined),
        label: Text(_downloading ? 'Downloading…' : 'Download PDF'),
        onPressed: _downloading ? null : _download,
      );
    }
    return const SizedBox.shrink();
  }
}

/// The projects this paper is in, plus a chip to add it to more.
class _ProjectChips extends ConsumerWidget {
  const _ProjectChips({required this.paperId});

  final String paperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects =
        ref.watch(projectsForPaperProvider(paperId)).value ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final project in projects)
            InputChip(
              avatar: const Icon(Icons.folder_special_outlined, size: 16),
              label: Text(project.name),
              onPressed: () =>
                  showProjectPickerSheet(context, paperId: paperId),
              onDeleted: () => removePaperFromProject(
                ref.read(databaseProvider),
                projectId: project.id,
                paperId: paperId,
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: Text(projects.isEmpty ? 'Add to project' : 'Project'),
            onPressed: () => showProjectPickerSheet(context, paperId: paperId),
          ),
        ],
      ),
    );
  }
}

/// To read / Reading / Done — tap a status again to clear it.
class _ReadingStatusRow extends ConsumerWidget {
  const _ReadingStatusRow({required this.paper});

  final Paper? paper;

  static const _labels = {
    ReadingStatus.toRead: 'To read',
    ReadingStatus.reading: 'Reading',
    ReadingStatus.done: 'Done',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = this.paper;
    if (paper == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        children: [
          for (final status in ReadingStatus.values)
            ChoiceChip(
              label: Text(_labels[status]!),
              selected: paper.readingStatus == status,
              onSelected: (selected) => setReadingStatus(
                ref.read(databaseProvider),
                paper.id,
                selected ? status : null,
              ),
            ),
          _StarRating(paper: paper),
        ],
      ),
    );
  }
}

/// Five stars for "how much this paper matters to me"; tap the current
/// rating to clear it.
class _StarRating extends ConsumerWidget {
  const _StarRating({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = paper.rating ?? 0;
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          InkResponse(
            key: ValueKey('star-$i'),
            radius: 18,
            onTap: () => setRating(
              ref.read(databaseProvider),
              paper.id,
              rating == i ? null : i,
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(
                i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 22,
                color: i <= rating ? color : color.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}

/// The paper's highlighted passages, each opening the PDF at its page.
/// Hidden until there is at least one.
class _HighlightsSection extends ConsumerWidget {
  const _HighlightsSection({required this.paper});

  final Paper? paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = this.paper;
    if (paper == null) return const SizedBox.shrink();
    final highlights =
        ref.watch(highlightsForPaperProvider(paper.id)).value ?? const [];
    if (highlights.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return _Section(
      title: 'Highlights',
      child: Column(
        children: [
          for (final h in highlights)
            ListTile(
              leading: Container(
                width: 5,
                height: 32,
                decoration: BoxDecoration(
                  color: colorFromHex(h.colorHex),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              title: Text(
                h.quote,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              subtitle: Text(
                ['p. ${h.pageNumber}', ?h.comment].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: paper.pdfPath == null
                  ? () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => HighlightSheet(highlightId: h.id),
                    )
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen(
                          paperId: paper.id,
                          pdfPath: paper.pdfPath!,
                          initialPage: h.pageNumber,
                        ),
                      ),
                    ),
              onLongPress: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => HighlightSheet(highlightId: h.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// A titled group on the paper screen: small header, content in a card.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(height: 4),
          Card(
            child: AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends ConsumerWidget {
  const _AttachmentTile({required this.attachment});

  final Attachment attachment;

  IconData get _icon {
    if (isAudioAttachment(attachment)) return Icons.headphones_outlined;
    switch (attachment.type) {
      case AttachmentType.podcast:
        return Icons.podcasts;
      case AttachmentType.image:
        return Icons.image_outlined;
      case AttachmentType.pdf:
        return Icons.picture_as_pdf_outlined;
      case AttachmentType.link:
        return Icons.link;
      case AttachmentType.file:
        return Icons.attach_file;
    }
  }

  /// Its file is in the cloud but hasn't been downloaded to this device.
  bool get _inCloudOnly =>
      attachment.path == null && attachment.storageKey != null;

  Future<void> _downloadThenOpen(
    BuildContext context,
    WidgetRef ref, {
    required bool audio,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final playback = ref.read(audioPlaybackProvider);
    final db = ref.read(databaseProvider);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Downloading…'),
        duration: Duration(seconds: 2),
      ),
    );
    final ok = await ref
        .read(syncServiceProvider)
        .downloadFile(attachmentId: attachment.id);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t download the file. Try again.'),
        ),
      );
      return;
    }
    if (!audio) return;
    final fresh = await (db.select(
      db.attachments,
    )..where((t) => t.id.equals(attachment.id))).getSingleOrNull();
    if (fresh != null) await playback.open(fresh);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = attachment;
    final audio = isAudioAttachment(a);
    final url = a.url;
    final playback = audio ? ref.watch(audioPlaybackProvider) : null;
    final playingThis =
        playback != null && playback.current?.id == a.id && playback.playing;

    return ListTile(
      leading: Icon(
        playingThis ? Icons.graphic_eq : _icon,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        a.title ?? a.url ?? a.path ?? 'Attachment',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: audio
          ? Icon(
              _inCloudOnly ? Icons.cloud_download_outlined : Icons.play_arrow,
            )
          : url != null
          ? const Icon(Icons.open_in_new, size: 20)
          : _inCloudOnly
          ? const Icon(Icons.cloud_download_outlined)
          : null,
      onTap: _inCloudOnly
          ? () => _downloadThenOpen(context, ref, audio: audio)
          : audio
          ? () => playback!.open(a)
          : url != null
          ? () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
          : null,
    );
  }
}
