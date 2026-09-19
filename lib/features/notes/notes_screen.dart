import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'note_editor_screen.dart';
import 'notes_providers.dart';

/// Distraction-free notes space: quick capture that mixes text, images,
/// and pen input in a single note.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  Future<void> _createNote(BuildContext context, WidgetRef ref) async {
    final id = const Uuid().v4();
    final db = ref.read(databaseProvider);
    await db.into(db.notes).insert(NotesCompanion.insert(id: Value(id)));
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);

    return Scaffold(
      body: notesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (notes) {
          if (notes.isEmpty) {
            return Center(
              child: Text(
                'No notes yet.\nTap + to capture your first one.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final note = notes[index];
              return ListTile(
                title: Text(
                  note.title.isEmpty ? 'Untitled' : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  note.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(DateFormat.MMMd().format(note.updatedAt)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(noteId: note.id),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNote(context, ref),
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }
}
