import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

/// A single note, editable in place with no separate "edit mode" — typing
/// autosaves after a short pause, so there's nothing to remember to save.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final int noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  Timer? _debounce;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
    _titleController.addListener(_scheduleSave);
    _contentController.addListener(_scheduleSave);
  }

  Future<void> _loadNote() async {
    final db = ref.read(databaseProvider);
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(widget.noteId))).getSingleOrNull();
    if (note != null && mounted) {
      _titleController.text = note.title;
      _contentController.text = note.content;
    }
    setState(() => _loaded = true);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    await (db.update(db.notes)..where((n) => n.id.equals(widget.noteId)))
        .write(
          NotesCompanion(
            title: Value(_titleController.text),
            content: Value(_contentController.text),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  controller: _contentController,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'Start writing…',
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                ),
              ],
            ),
    );
  }
}
