import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup.dart';
import '../../data/database_provider.dart';

/// Makes a backup zip and hands it to the share sheet (save to Files,
/// AirDrop, email, Drive…).
Future<void> backUpToFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparing backup…')));
  try {
    final db = ref.read(databaseProvider);
    final docs = await getApplicationDocumentsDirectory();
    final out = await getTemporaryDirectory();
    final zip = await createBackup(db, docsDir: docs, outDir: out);
    messenger.hideCurrentSnackBar();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(zip.path)], subject: 'Corplex backup'),
    );
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Couldn\'t create the backup.')),
      );
  }
}

/// Picks a backup, confirms what's in it, stages it, and tells the user to
/// reopen the app (the swap happens at launch, before the database opens).
Future<void> restoreFromBackupFile(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  if (picked?.path == null || !context.mounted) return;

  final db = ref.read(databaseProvider);
  final zip = File(picked!.path!);
  final BackupInfo info;
  try {
    info = inspectBackup(zip, currentSchemaVersion: db.schemaVersion);
  } on BackupException catch (e) {
    await _notice(context, 'Can\'t restore', e.message);
    return;
  }
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        'From ${DateFormat.yMMMd().add_jm().format(info.createdAt)}: '
        '${info.notes} note${info.notes == 1 ? '' : 's'} and '
        '${info.papers} paper${info.papers == 1 ? '' : 's'}.\n\n'
        'It replaces what\'s on this device now. Your current library is '
        'kept aside in case you change your mind.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Restore'),
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
    if (context.mounted) await _notice(context, 'Can\'t restore', e.message);
    return;
  }
  if (!context.mounted) return;
  await _notice(
    context,
    'One more step',
    'Close Corplex completely and open it again to finish restoring.',
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
