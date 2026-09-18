import 'package:drift/drift.dart';

/// A single note. Content is stored as a JSON-encoded rich document so a
/// note can mix text, images, and pen strokes in one flow.
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
