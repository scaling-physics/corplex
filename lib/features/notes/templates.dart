import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../lock/note_lock_service.dart';
import '../lock/notes_password_dialogs.dart';
import '../platform/mac_window.dart' show isDesktop;
import '../projects/readable_content.dart';
import 'daily_notes.dart';
import 'editor_document.dart';
import 'note_templates.dart';
import 'notes_screen.dart' show createNote;
import 'template_variables.dart';

/// The notes marked as templates, by title. Live; empty until the reader
/// uses a note as a template, which is also when every template affordance
/// (the Templates filter, the long-press sheet, "Insert template") appears.
final templateNotesProvider = StreamProvider.autoDispose<List<Note>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.notes)
        ..where((n) => n.isTemplate.equals(true))
        ..orderBy([
          (n) => OrderingTerm.asc(n.title),
          (n) => OrderingTerm.asc(n.createdAt),
        ]))
      .watch();
});

/// Marks [noteId] as a template (it leaves the ordinary lists) or takes it
/// back.
Future<void> setNoteTemplate(AppDatabase db, String noteId, bool template) =>
    (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(isTemplate: Value(template)),
    );

/// What the reader picked: a template note, or the built-in literature
/// note skeleton.
class TemplateChoice {
  const TemplateChoice.note(String this.noteId);
  const TemplateChoice.literature() : noteId = null;

  /// The template note's id; null for the literature skeleton.
  final String? noteId;
  bool get isLiterature => noteId == null;
}

/// A template's name in a list.
String templateLabel(Note template, AppLocalizations l10n) =>
    template.title.trim().isEmpty ? l10n.templatesUntitled : template.title;

/// The rows of the template pickers: the literature skeleton (when
/// [includeLiterature]) then every template.
Widget _choiceList(
  BuildContext context,
  List<Note> templates, {
  required bool includeLiterature,
  required ValueChanged<TemplateChoice> onPick,
  List<Widget> leading = const [],
}) {
  final l10n = context.l10n;
  final dense = isDesktop(context);
  return SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...leading,
        if (includeLiterature)
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(l10n.templatesLiterature),
            subtitle: Text(l10n.editorTemplateHint),
            dense: dense,
            onTap: () => onPick(const TemplateChoice.literature()),
          ),
        for (final t in templates)
          ListTile(
            key: ValueKey('template-${t.id}'),
            leading: const Icon(Icons.description_outlined),
            title: Text(templateLabel(t, l10n)),
            dense: dense,
            onTap: () => onPick(TemplateChoice.note(t.id)),
          ),
      ],
    ),
  );
}

Future<T?> _showPanel<T>(BuildContext context, WidgetBuilder builder) {
  // A desktop shows a small panel in the middle of the window; a bottom
  // sheet would sit alone at the foot of a very wide one.
  if (isDesktop(context)) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: builder(context),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(child: builder(context)),
  );
}

/// Asks which template to use. Null if dismissed (or, with
/// [includeLiterature] false, if there are no templates).
Future<TemplateChoice?> pickTemplate(
  BuildContext context,
  WidgetRef ref, {
  bool includeLiterature = true,
}) async {
  final templates = await ref.read(templateNotesProvider.future);
  if (!context.mounted) return null;
  if (templates.isEmpty && !includeLiterature) return null;
  return _showPanel<TemplateChoice>(
    context,
    (context) => _choiceList(
      context,
      templates,
      includeLiterature: includeLiterature,
      onPick: (c) => Navigator.pop(context, c),
    ),
  );
}

/// The stored body of template [id] with its variables filled in for a new
/// note titled [title]; null if it can't be read (gone, or locked and the
/// reader didn't unlock). A locked template asks for the notes password.
Future<String?> readTemplateBody(
  BuildContext context,
  WidgetRef ref,
  String id, {
  required String title,
  DateTime? now,
}) async {
  final db = ref.read(databaseProvider);
  final l10n = context.l10n;
  final template = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(id))).getSingleOrNull();
  if (template == null || !context.mounted) return null;
  final locale = l10n.localeName;
  var content = template.content;
  if (isLockedContent(content)) {
    final lock = ref.read(noteLockServiceProvider);
    if (!lock.canRead(content)) {
      final ok = await requestNotesUnlock(
        context,
        lock,
        reason: l10n.templatesUnlockReason,
      );
      if (!ok) return null;
    }
    final readable = await readableNoteContent(lock, template.id, content);
    if (readable == null) return null;
    content = readable;
  }
  return expandTemplateContent(
    content,
    now: now ?? DateTime.now(),
    title: title,
    locale: locale,
  );
}

/// The ids of the tags on [noteId].
Future<List<String>> _tagIdsOf(AppDatabase db, String noteId) async {
  final rows = await (db.select(
    db.noteTags,
  )..where((r) => r.noteId.equals(noteId))).get();
  return [for (final r in rows) r.tagId];
}

/// Creates a note from template [templateId] — its body (variables filled
/// in) and tags; the title is the template's title with variables filled in
/// if it has any, else empty — and opens it.
Future<void> createNoteFromTemplate(
  BuildContext context,
  WidgetRef ref,
  String templateId, {
  DateTime? now,
}) async {
  final db = ref.read(databaseProvider);
  final template = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(templateId))).getSingleOrNull();
  if (template == null || !context.mounted) return;
  final moment = now ?? DateTime.now();
  final locale = context.l10n.localeName;
  final title = hasTemplateVariables(template.title)
      ? expandTemplateVariables(template.title, now: moment, locale: locale)
      : '';
  final body = await readTemplateBody(
    context,
    ref,
    templateId,
    title: title,
    now: moment,
  );
  if (body == null || !context.mounted) return;
  final tags = await _tagIdsOf(db, templateId);
  if (!context.mounted) return;
  await createNote(context, ref, title: title, content: body, tagIds: tags);
}

/// A new note holding the literature skeleton, opened.
Future<void> createLiteratureNote(BuildContext context, WidgetRef ref) =>
    createNote(context, ref, content: literatureNoteContent(context.l10n));

/// Makes a note from [choice] and opens it.
Future<void> createNoteFromChoice(
  BuildContext context,
  WidgetRef ref,
  TemplateChoice choice,
) => choice.isLiterature
    ? createLiteratureNote(context, ref)
    : createNoteFromTemplate(context, ref, choice.noteId!);

/// File → New Note from Template…, and the sheet's templates: pick one,
/// then make the note.
Future<void> newNoteFromTemplate(BuildContext context, WidgetRef ref) async {
  final choice = await pickTemplate(context, ref);
  if (choice == null || !context.mounted) return;
  await createNoteFromChoice(context, ref, choice);
}

/// The sheet behind a long-press (or secondary click) on the New note
/// button: Today's note, then the literature skeleton and the templates.
/// Nothing on screen advertises it.
Future<void> showNewNoteSheet(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final templates = await ref.read(templateNotesProvider.future);
  if (!context.mounted) return;
  HapticFeedback.selectionClick();
  final result = await _showPanel<Object>(
    context,
    (context) => _choiceList(
      context,
      templates,
      includeLiterature: true,
      onPick: (c) => Navigator.pop(context, c),
      leading: [
        ListTile(
          key: const ValueKey('new-note-today'),
          leading: const Icon(Icons.today_outlined),
          title: Text(l10n.dailyTodaysNote),
          dense: isDesktop(context),
          onTap: () => Navigator.pop(context, 'today'),
        ),
        const Divider(height: 1),
      ],
    ),
  );
  if (result == null || !context.mounted) return;
  if (result == 'today') {
    await openTodaysNote(context, ref);
  } else if (result is TemplateChoice) {
    await createNoteFromChoice(context, ref, result);
  }
}

/// Wraps the New note button so a long-press (touch) or secondary click
/// (mouse) opens [showNewNoteSheet]. A plain tap still reaches [child].
class NewNoteMenuRegion extends ConsumerWidget {
  const NewNoteMenuRegion({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// False on the Library tab, where the button imports a PDF instead.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onLongPress: enabled ? () => showNewNoteSheet(context, ref) : null,
    onSecondaryTap: enabled ? () => showNewNoteSheet(context, ref) : null,
    child: child,
  );
}

/// Inserts [stored] (a note body in stored form, variables already filled
/// in) into [controller] at [index] on a fresh line. It goes through
/// [editorDocument], so citations, maths and figure markers in the template
/// become chips, and is composed as a Delta so formatting and embeds
/// survive. The caret ends at the end of the inserted text. Returns the
/// caret offset.
int insertTemplateBody(QuillController controller, int index, String stored) {
  var at = index;
  final doc = controller.document;
  // Start on a fresh line.
  if (at > 0 && doc.toPlainText()[at - 1] != '\n') {
    controller.replaceText(at, 0, '\n', null);
    at++;
  }
  final template = editorDocument(stored).toDelta();
  // `concat` returns the joined delta; it doesn't change either.
  final delta = (Delta()..retain(at)).concat(template);
  // `Delta.length` counts operations; the text length is the sum of theirs.
  final end =
      at + template.toList().fold<int>(0, (n, op) => n + (op.length ?? 0)) - 1;
  controller.compose(delta, controller.selection, ChangeSource.local);
  controller.updateSelection(
    TextSelection.collapsed(offset: end),
    ChangeSource.local,
  );
  return end;
}

/// `/` → Insert template in a note: picks a template (or the literature
/// skeleton, via [insertLiterature]) and writes it at the caret.
/// [noteTitle] fills `{{title}}`.
Future<void> pickAndInsertTemplate(
  BuildContext context,
  WidgetRef ref,
  QuillController controller, {
  required String noteTitle,
  required VoidCallback insertLiterature,
}) async {
  final choice = await pickTemplate(context, ref);
  if (choice == null || !context.mounted) return;
  if (choice.isLiterature) {
    insertLiterature();
    return;
  }
  final body = await readTemplateBody(
    context,
    ref,
    choice.noteId!,
    title: noteTitle,
  );
  if (body == null) return;
  final docEnd = controller.document.length - 1;
  final cursor = controller.selection.baseOffset;
  insertTemplateBody(
    controller,
    cursor < 0 || cursor > docEnd ? docEnd : cursor,
    body,
  );
}
