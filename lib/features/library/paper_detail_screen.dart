import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../notes/note_editor_screen.dart';
import 'add_attachment_sheet.dart';
import 'citation_formatter.dart';
import 'papers_providers.dart';
import 'pdf_viewer_screen.dart';

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
    await (db.update(db.papers)..where((p) => p.id.equals(widget.paperId)))
        .write(
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
      body: !_loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                TextField(
                  controller: _titleController,
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                  ),
                ),
                TextField(
                  controller: _authorsController,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    hintText: 'Authors',
                    border: InputBorder.none,
                  ),
                ),
                if (paperAsync.value?.pdfPath case final pdfPath?) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('View PDF'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen(
                          paperId: widget.paperId,
                          pdfPath: pdfPath,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attachments',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add attachment',
                      onPressed: () =>
                          showAddAttachmentSheet(context, ref, widget.paperId),
                    ),
                  ],
                ),
                attachmentsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, _) => Text('Could not load attachments: $error'),
                  data: (attachments) {
                    if (attachments.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No attachments yet.'),
                      );
                    }
                    return Column(
                      children: attachments
                          .map((a) => _AttachmentTile(attachment: a))
                          .toList(),
                    );
                  },
                ),
                if (paperAsync.value case final paper?) ...[
                  const SizedBox(height: 24),
                  Text('Citation', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<CitationStyle>(
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
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            formatCitation(paper, _citationStyle),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
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
                      ],
                    ),
                  ),
                ],
                if (notesAsync.value case final notes? when notes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Referenced in notes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ...notes.map(
                    (note) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_note_outlined),
                      title: Text(
                        note.title.isEmpty ? 'Untitled' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NoteEditorScreen(noteId: note.id),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment});

  final Attachment attachment;

  IconData get _icon {
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
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon),
      title: Text(
        attachment.title ?? attachment.url ?? attachment.path ?? 'Attachment',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
