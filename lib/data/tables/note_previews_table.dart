import 'package:drift/drift.dart';

import 'notes_table.dart';

/// The one-line text the Notes list shows under a title, so the list never
/// has to load (or decode) whole note bodies. Derived data, local to this
/// device and deliberately *not* synced or backed up: a missing row means
/// "stale", and the list rebuilds it on demand.
///
/// SQLite triggers (`notePreviewStatements` in `database.dart`) delete a
/// note's row whenever its `content` changes, by any path — editor saves,
/// sync's raw SQL, restores — so nothing in app code has to remember to.
/// A locked note's row has `locked = 1` and an empty preview: the plain text
/// of a locked note is never stored here.
class NotePreviews extends Table {
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get preview => text().withDefault(const Constant(''))();
  BoolColumn get locked => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {noteId};
}
