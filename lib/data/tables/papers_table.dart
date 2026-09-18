import 'package:drift/drift.dart';

/// A referenced paper/source, the unit the Library tab lists and searches.
class Papers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get authors => text().withDefault(const Constant(''))();
  IntColumn get year => integer().nullable()();
  TextColumn get venue => text().nullable()();
  TextColumn get doi => text().nullable()();

  /// Local file path to the imported PDF, if any.
  TextColumn get pdfPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
