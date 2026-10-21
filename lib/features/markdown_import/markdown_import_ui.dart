import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import 'markdown_importer.dart';
import 'vault_source.dart';

/// Where the import's files come from. The real picker asks the system;
/// tests override [markdownImportPickerProvider].
abstract class MarkdownImportPicker {
  /// A folder (an Obsidian vault), or null when cancelled.
  Future<List<MdSourceFile>?> pickFolder();

  /// One or more `.md` files, or null when cancelled.
  Future<List<MdSourceFile>?> pickFiles();

  /// A `.zip` of Markdown files, or null when cancelled.
  Future<List<MdSourceFile>?> pickZip();
}

class SystemMarkdownImportPicker implements MarkdownImportPicker {
  const SystemMarkdownImportPicker();

  @override
  Future<List<MdSourceFile>?> pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return null;
    return loadVaultDirectory(Directory(path));
  }

  @override
  Future<List<MdSourceFile>?> pickFiles() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown'],
    );
    final paths = [
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty) return null;
    return loadMarkdownFiles(paths);
  }

  @override
  Future<List<MdSourceFile>?> pickZip() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = picked?.path;
    if (path == null) return null;
    return loadVaultZip(File(path));
  }
}

final markdownImportPickerProvider = Provider<MarkdownImportPicker>(
  (ref) => const SystemMarkdownImportPicker(),
);

enum _Source { folder, files, zip }

/// Account sheet / File menu: choose a source, import with a progress
/// dialog, then summarise what happened.
Future<void> importMarkdownVault(BuildContext context, WidgetRef ref) async {
  final source = await showDialog<_Source>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.l10n.mdImportChooseTitle),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _Source.folder),
          child: ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(context.l10n.mdImportFolder),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _Source.files),
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(context.l10n.mdImportFiles),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _Source.zip),
          child: ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: Text(context.l10n.mdImportZip),
          ),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return;

  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final db = ref.read(databaseProvider);
  final picker = ref.read(markdownImportPickerProvider);

  final progress = ValueNotifier<(int, int)?>(null);
  var dialogOpen = false;
  void openProgress() {
    if (dialogOpen || !context.mounted) return;
    dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: ValueListenableBuilder<(int, int)?>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value == null
                        ? context.l10n.mdImportReading
                        : context.l10n.mdImportProgress(value.$1, value.$2),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: value == null || value.$2 == 0
                        ? null
                        : value.$1 / value.$2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void closeProgress() {
    if (!dialogOpen) return;
    dialogOpen = false;
    navigator.pop();
  }

  MdImportSummary? summary;
  var readFailed = false;
  try {
    final files = switch (source) {
      _Source.folder => await picker.pickFolder(),
      _Source.files => await picker.pickFiles(),
      _Source.zip => await picker.pickZip(),
    };
    if (files == null) return;
    if (!files.any((f) => isMarkdownPath(f.path))) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mdImportNothing)));
      return;
    }
    openProgress();
    summary = await importMarkdown(
      db,
      files,
      onProgress: (done, total) => progress.value = (done, total),
    );
  } catch (_) {
    readFailed = true;
  } finally {
    closeProgress();
    progress.dispose();
  }
  if (readFailed) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.mdImportReadFailed)));
    return;
  }
  if (summary == null || !context.mounted) return;
  final s = summary;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.mdImportDoneTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.mdImportSummaryNotes(s.notes)),
          if (s.attachments > 0)
            Text(context.l10n.mdImportSummaryAttachments(s.attachments)),
          if (s.unresolved > 0)
            Text(context.l10n.mdImportSummaryUnresolved(s.unresolved)),
          if (s.skipped > 0)
            Text(context.l10n.mdImportSummarySkipped(s.skipped)),
          if (s.failed > 0) Text(context.l10n.mdImportSummaryFailed(s.failed)),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonOk),
        ),
      ],
    ),
  );
}
