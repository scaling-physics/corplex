import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import 'tags_providers.dart';

Future<void> showTagPickerSheet(BuildContext context, WidgetRef ref, String noteId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TagPickerSheet(noteId: noteId),
  );
}

class _TagPickerSheet extends ConsumerStatefulWidget {
  const _TagPickerSheet({required this.noteId});

  final String noteId;

  @override
  ConsumerState<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<_TagPickerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(tagsListProvider);
    final currentAsync = ref.watch(tagsForNoteProvider(widget.noteId));
    final currentIds =
        currentAsync.value?.map((t) => t.id).toSet() ?? <String>{};

    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'New tag name',
                        ),
                        onSubmitted: (_) => _createAndAdd(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add tag',
                      onPressed: _createAndAdd,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: switch (tagsAsync.value) {
                  null => const SizedBox.shrink(),
                  [] => const Center(child: Text('No tags yet.')),
                  final tags => ListView(
                    children: tags.map((tag) {
                      final added = currentIds.contains(tag.id);
                      return ListTile(
                        title: Text('#${tag.name}'),
                        trailing: Icon(
                          added ? Icons.check_circle : Icons.add_circle_outline,
                        ),
                        onTap: () => _toggle(tag.id, added),
                      );
                    }).toList(),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(String tagId, bool currentlyAdded) async {
    final db = ref.read(databaseProvider);
    if (currentlyAdded) {
      await removeTagFromNote(db, noteId: widget.noteId, tagId: tagId);
    } else {
      await addTagToNote(db, noteId: widget.noteId, tagId: tagId);
    }
  }

  Future<void> _createAndAdd() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    final tagId = await findOrCreateTag(db, name);
    await addTagToNote(db, noteId: widget.noteId, tagId: tagId);
    _controller.clear();
  }
}
