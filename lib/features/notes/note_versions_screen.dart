import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database_provider.dart';
import '../../theme/motion_widgets.dart';
import '../export/unlock_for_export.dart' show requestUnlock;
import '../home/adaptive.dart' show ReadableColumn;
import '../lock/note_lock_service.dart';
import 'note_versions.dart';

/// Opens the saved versions of a note. [flush] lets the open editor save
/// pending typing first, so "now" (the comparison, and a restore) is what
/// the reader sees.
Future<void> showNoteVersions(
  BuildContext context, {
  required String noteId,
  required Future<void> Function() flush,
}) async {
  await flush();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NoteVersionsScreen(noteId: noteId, flush: flush),
    ),
  );
}

String _when(DateTime t) => DateFormat.yMMMd().add_jm().format(t);

String _signed(int n) => n > 0 ? '+$n' : (n < 0 ? '−${-n}' : '0');

/// " · +340 since" / " · −120 since"; nothing when the length is the same.
String _since(int n) => n > 0
    ? ' · +$n since'
    : n < 0
    ? ' · −${-n} since'
    : '';

/// Asks for an optional name; null means cancelled, empty means no name.
Future<String?> _askLabel(
  BuildContext context, {
  required String title,
  required String action,
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
        decoration: const InputDecoration(hintText: 'Name (optional)'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
}

/// A note's saved versions, newest first.
class NoteVersionsScreen extends ConsumerWidget {
  const NoteVersionsScreen({
    super.key,
    required this.noteId,
    required this.flush,
  });

  final String noteId;
  final Future<void> Function() flush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(noteVersionsProvider(noteId)).value ?? const [];
    final note = ref.watch(versionNoteProvider(noteId)).value;
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);
    // Plain text of the bodies that can be read now (locked ones only
    // while unlocked); words are shown only for those.
    final texts = ref.watch(versionTextsProvider(noteId)).value ?? const {};
    final nowText = texts['note'];
    final nowWords = nowText == null ? null : noteWordCount(nowText);

    Future<void> save() async {
      final label = await _askLabel(
        context,
        title: 'Save a version',
        action: 'Save',
      );
      if (label == null) return;
      await flush();
      await saveNoteVersion(db, noteId, label: label);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Versions'),
        actions: [
          TextButton.icon(
            onPressed: note == null ? null : save,
            icon: const Icon(Icons.add),
            label: const Text('Save a version now'),
          ),
        ],
      ),
      body: ReadableColumn(
        child: versions.isEmpty
            ? const EmptyState(
                icon: Icons.history,
                title: 'No versions yet',
                message:
                    'A version is a saved copy of this note. One is kept '
                    'automatically when a chapter goes to your supervisor, '
                    'and you can save one any time.',
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  for (final v in versions)
                    ListTile(
                      title: Text(v.label ?? 'Saved version'),
                      subtitle: Text(
                        texts[v.id] == null
                            ? '${_when(v.createdAt)} · Locked'
                            : '${_when(v.createdAt)} · '
                                  '${noteWordCount(texts[v.id]!)} words'
                                  '${nowWords == null ? '' : _since(nowWords - noteWordCount(texts[v.id]!))}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NoteVersionCompareScreen(
                            versionId: v.id,
                            noteId: noteId,
                            flush: flush,
                          ),
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Version options',
                        onSelected: (choice) async {
                          if (choice == 'rename') {
                            final label = await _askLabel(
                              context,
                              title: 'Rename version',
                              action: 'Rename',
                              initial: v.label ?? '',
                            );
                            if (label != null) {
                              await setVersionLabel(db, v.id, label);
                            }
                          } else {
                            final row = await deleteNoteVersion(db, v.id);
                            if (row == null || !context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: const Text('Version deleted'),
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () =>
                                        undoDeleteNoteVersion(db, row),
                                  ),
                                ),
                              );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// One version against the note as it is now: lines added since are
/// tinted, lines removed since are struck through. Long unchanged runs
/// fold into one quiet line.
class NoteVersionCompareScreen extends ConsumerWidget {
  const NoteVersionCompareScreen({
    super.key,
    required this.versionId,
    required this.noteId,
    required this.flush,
  });

  final String versionId;
  final String noteId;
  final Future<void> Function() flush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(noteVersionsProvider(noteId)).value ?? const [];
    final note = ref.watch(versionNoteProvider(noteId)).value;
    final version = versions.where((v) => v.id == versionId).firstOrNull;
    final db = ref.read(databaseProvider);
    final lock = ref.read(noteLockServiceProvider);
    final scheme = Theme.of(context).colorScheme;

    if (version == null || note == null) {
      return Scaffold(appBar: AppBar(title: const Text('Compare')));
    }

    // Locked bodies are readable only while unlocked (the provider
    // refreshes when that changes); until then, ask.
    final texts = ref.watch(versionTextsProvider(noteId)).value;
    final versionText = texts?[version.id];
    final noteText = texts?['note'];
    if (texts == null || versionText == null || noteText == null) {
      return Scaffold(
        appBar: AppBar(title: Text(version.label ?? 'Saved version')),
        body: texts == null
            ? const SizedBox.shrink()
            : EmptyState(
                icon: Icons.lock_outline,
                title: 'Locked',
                message: 'Unlock this note to compare or restore versions.',
                action: FilledButton(
                  onPressed: () => requestUnlock(
                    context,
                    lock,
                    reason: 'Unlock this note to compare its versions.',
                  ),
                  child: const Text('Unlock'),
                ),
              ),
      );
    }

    final diff = [
      if (version.title != note.title) ...[
        DiffLine(DiffKind.removed, version.title),
        DiffLine(DiffKind.added, note.title),
      ],
      ...diffLines(noteLines(versionText), noteLines(noteText)),
    ].where((l) => l.text.trim().isNotEmpty).toList();
    final added = diff.where((l) => l.kind == DiffKind.added).length;
    final removed = diff.where((l) => l.kind == DiffKind.removed).length;
    final words = noteWordCount(noteText) - noteWordCount(versionText);

    Future<void> restore() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this version?'),
          content: const Text(
            'The note goes back to this version. What is there now is '
            'saved first as "$beforeRestoringLabel".',
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
      if (ok != true) return;
      await flush();
      try {
        await restoreNoteVersion(db, versionId, lock: lock);
      } on NoteLockedException {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unlock the note to restore it.')),
        );
        return;
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Version restored')));
    }

    // Fold runs of more than 4 unchanged lines.
    final rows = <Widget>[];
    var run = <DiffLine>[];
    void flushRun() {
      if (run.length > 4) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              '${run.length} unchanged lines',
              style: TextStyle(color: scheme.outline),
            ),
          ),
        );
      } else {
        rows.addAll(run.map((l) => _line(l, scheme)));
      }
      run = [];
    }

    for (final l in diff) {
      if (l.kind == DiffKind.same) {
        run.add(l);
      } else {
        flushRun();
        rows.add(_line(l, scheme));
      }
    }
    flushRun();

    return Scaffold(
      appBar: AppBar(
        title: Text(version.label ?? 'Saved version'),
        actions: [
          TextButton(
            onPressed: restore,
            child: const Text('Restore this version'),
          ),
        ],
      ),
      body: ReadableColumn(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                diff.isEmpty
                    ? '${_when(version.createdAt)} · the same as now'
                    : '${_when(version.createdAt)} · now has '
                          '${_signed(words)} words · '
                          '$added added, $removed removed',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _line(DiffLine l, ColorScheme scheme) {
    final (bg, fg, decoration) = switch (l.kind) {
      DiffKind.added => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        null,
      ),
      DiffKind.removed => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        TextDecoration.lineThrough,
      ),
      DiffKind.same => (null, scheme.onSurfaceVariant, null),
    };
    return Container(
      key: ValueKey('diff-${l.kind.name}'),
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Text(
        l.text,
        style: TextStyle(color: fg, decoration: decoration),
      ),
    );
  }
}
