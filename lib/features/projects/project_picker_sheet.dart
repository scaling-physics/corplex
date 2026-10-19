import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../data/database_provider.dart';
import 'projects_providers.dart';

/// Which projects a paper or note is in: tick to add, untick to remove,
/// or type a name to create a project and add it in one step. Give exactly
/// one of [paperId] / [noteId].
Future<void> showProjectPickerSheet(
  BuildContext context, {
  String? paperId,
  String? noteId,
}) {
  assert((paperId == null) != (noteId == null), 'pass a paper or a note');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProjectPickerSheet(paperId: paperId, noteId: noteId),
  );
}

class _ProjectPickerSheet extends ConsumerStatefulWidget {
  const _ProjectPickerSheet({this.paperId, this.noteId});

  final String? paperId;
  final String? noteId;

  @override
  ConsumerState<_ProjectPickerSheet> createState() =>
      _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends ConsumerState<_ProjectPickerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _set(String projectId, {required bool member}) async {
    final db = ref.read(databaseProvider);
    if (widget.paperId case final paperId?) {
      member
          ? await addPaperToProject(db, projectId: projectId, paperId: paperId)
          : await removePaperFromProject(
              db,
              projectId: projectId,
              paperId: paperId,
            );
    } else {
      final noteId = widget.noteId!;
      member
          ? await addNoteToProject(db, projectId: projectId, noteId: noteId)
          : await removeNoteFromProject(
              db,
              projectId: projectId,
              noteId: noteId,
            );
    }
  }

  Future<void> _createAndAdd() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final id = await findOrCreateProject(ref.read(databaseProvider), name);
    await _set(id, member: true);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsListProvider).value ?? const [];
    final current =
        (widget.paperId != null
                ? ref.watch(projectsForPaperProvider(widget.paperId!))
                : ref.watch(projectsForNoteProvider(widget.noteId!)))
            .value;
    final currentIds = {for (final p in current ?? const []) p.id};

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: context.l10n.projectsNewProject,
                        ),
                        onSubmitted: (_) => _createAndAdd(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: context.l10n.projectsCreateAndAdd,
                      onPressed: _createAndAdd,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: projects.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        child: Text(context.l10n.projectsPickerIntro),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final project in projects)
                            CheckboxListTile(
                              value: currentIds.contains(project.id),
                              title: Text(project.name),
                              secondary: const Icon(
                                Icons.folder_special_outlined,
                              ),
                              onChanged: (v) =>
                                  _set(project.id, member: v ?? false),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
