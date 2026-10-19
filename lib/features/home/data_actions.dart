import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../platform/share_origin.dart';
import '../../data/backup.dart';
import '../../data/database_provider.dart';
import '../export/vault_export.dart';

/// Makes a backup zip and hands it to the share sheet (save to Files,
/// AirDrop, email, Drive…).
Future<void> backUpToFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final origin = shareOrigin(context);
  final l10n = context.l10n;
  messenger.showSnackBar(SnackBar(content: Text(l10n.settingsPreparingBackup)));
  try {
    final db = ref.read(databaseProvider);
    final docs = await getApplicationDocumentsDirectory();
    final out = await getTemporaryDirectory();
    final zip = await createBackup(db, docsDir: docs, outDir: out);
    messenger.hideCurrentSnackBar();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zip.path)],
        subject: l10n.settingsBackupSubject,
        sharePositionOrigin: origin,
      ),
    );
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.settingsBackupFailed)));
  }
}

/// Exports notes, papers and highlights as an Obsidian-friendly Markdown
/// folder (zipped) and opens the share sheet. Asks whether to include PDFs.
Future<void> exportAsMarkdown(BuildContext context, WidgetRef ref) async {
  final origin = shareOrigin(context);
  final l10n = context.l10n;
  var includePdfs = false;
  // An export is a plain-text copy on disk, so locked notes go out as
  // placeholders (even when unlocked); say so only when there are any.
  final anyLocked = await anyLockedNotes(ref.read(databaseProvider));
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.l10n.settingsExportMarkdown),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.settingsExportBody),
            if (anyLocked) ...[
              const SizedBox(height: 8),
              Text(context.l10n.settingsExportLocked),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.settingsIncludePdfs),
              subtitle: Text(context.l10n.settingsIncludePdfsSubtitle),
              value: includePdfs,
              onChanged: (v) => setState(() => includePdfs = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.settingsExport),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final db = ref.read(databaseProvider);
  final out = await getTemporaryDirectory();
  if (!context.mounted) return;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
  );
  File? zip;
  try {
    zip = await writeVaultZip(db, outDir: out, includePdfs: includePdfs);
  } catch (_) {
    zip = null;
  }
  navigator.pop();
  if (zip == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsExportFailed)));
    return;
  }
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(zip.path)],
      subject: l10n.settingsExportSubject,
      sharePositionOrigin: origin,
    ),
  );
}

/// Picks a backup, confirms what's in it, stages it, and tells the user to
/// reopen the app (the swap happens at launch, before the database opens).
Future<void> restoreFromBackupFile(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  if (picked?.path == null || !context.mounted) return;

  final l10n = context.l10n;
  final locale = Localizations.localeOf(context).toString();
  final db = ref.read(databaseProvider);
  final zip = File(picked!.path!);
  final BackupInfo info;
  try {
    info = inspectBackup(zip, currentSchemaVersion: db.schemaVersion);
  } on BackupException catch (e) {
    await _notice(context, l10n.settingsCantRestore, _problemText(l10n, e));
    return;
  }
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.settingsRestoreTitle),
      content: Text(
        l10n.settingsRestoreBody(
          DateFormat.yMMMd(locale).add_jm().format(info.createdAt),
          info.notes,
          info.papers,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.settingsRestoreAction),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final docs = await getApplicationDocumentsDirectory();
  try {
    await stageRestore(
      zip,
      docsDir: docs,
      currentSchemaVersion: db.schemaVersion,
    );
  } on BackupException catch (e) {
    if (context.mounted) {
      await _notice(context, l10n.settingsCantRestore, _problemText(l10n, e));
    }
    return;
  }
  if (!context.mounted) return;
  await _notice(
    context,
    l10n.settingsOneMoreStep,
    l10n.settingsRestartToFinish,
  );
}

Future<void> _notice(BuildContext context, String title, String message) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonOk),
          ),
        ],
      ),
    );

String _problemText(AppLocalizations l10n, BackupException e) =>
    switch (e.problem) {
      BackupProblem.notABackup => l10n.dataNotABackup,
      BackupProblem.unsupportedVersion => l10n.dataUnsupportedVersion,
      BackupProblem.newerVersion => l10n.dataNewerVersion,
    };
