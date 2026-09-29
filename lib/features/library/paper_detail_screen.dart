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
import 'citation_formatter.dart';
import 'papers_providers.dart';
import 'pdf_viewer_screen.dart';
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
  Timer? _debounce;
  bool _loaded = false;
  CitationStyle _citationStyle = CitationStyle.apa;

  @override
  void initState() {
    super.initState();
    _loadPaper();
    _titleController.addListener(_scheduleSave);
    _authorsController.addListener(_scheduleSave);
  }

  Future<void> _loadPaper() async {
    final db = ref.read(databaseProvider);
    final paper = await (db.select(
      db.papers,
    )..where((p) => p.id.equals(widget.paperId))).getSingleOrNull();
    if (paper != null && mounted) {
      _titleController.text = paper.title;
      _authorsController.text = paper.authors;
    }
    setState(() => _loaded = true);
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
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _authorsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachmentsAsync = ref.watch(
      attachmentsForPaperProvider(widget.paperId),
    );
    final paperAsync = ref.watch(paperByIdProvider(widget.paperId));
    final notesAsync = ref.watch(notesForPaperProvider(widget.paperId));

    return Scaffold(
      appBar: AppBar(),
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

/// "Open PDF" when the file is on this device; a quiet placeholder while
/// sync is still downloading it; nothing for papers without a PDF.
class _PdfButton extends StatelessWidget {
  const _PdfButton({required this.paperId, required this.paper});

  final String paperId;
  final Paper? paper;

  @override
  Widget build(BuildContext context) {
    final paper = this.paper;
    if (paper == null) return const SizedBox.shrink();
    if (paper.pdfPath case final pdfPath?) {
      return FilledButton.tonalIcon(
        icon: const Icon(Icons.menu_book_outlined),
        label: const Text('Open PDF'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(paperId: paperId, pdfPath: pdfPath),
          ),
        ),
      );
    }
    if (paper.storageKey != null) {
      return FilledButton.tonalIcon(
        icon: const Icon(Icons.cloud_download_outlined),
        label: const Text('PDF is syncing to this device…'),
        onPressed: null,
      );
    }
    return const SizedBox.shrink();
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
          ? const Icon(Icons.play_arrow)
          : url != null
          ? const Icon(Icons.open_in_new, size: 20)
          : null,
      onTap: audio
          ? () => playback!.open(a)
          : url != null
          ? () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
          : null,
    );
  }
}
