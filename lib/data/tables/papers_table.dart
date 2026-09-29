import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Where a paper is in the reader's queue.
enum ReadingStatus { toRead, reading, done }

/// A referenced paper/source, the unit the Library tab lists and searches.
/// Primary key is a client-generated UUID (see notes_table.dart for why).
class Papers extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get title => text()();
  TextColumn get authors => text().withDefault(const Constant(''))();
  IntColumn get year => integer().nullable()();
  TextColumn get venue => text().nullable()();
  TextColumn get doi => text().nullable()();

  /// Local file path to the imported PDF, if any.
  TextColumn get pdfPath => text().nullable()();

  /// Object key of the PDF in cloud storage once uploaded (synced, unlike
  /// [pdfPath], which only means something on this device).
  TextColumn get storageKey => text().nullable()();

  /// The page the reader was last on, so the paper reopens there.
  IntColumn get lastPage => integer().nullable()();

  /// Where the paper is in the reader's queue (see [ReadingStatus]); null
  /// means not yet triaged.
  TextColumn get readingStatus => textEnum<ReadingStatus>().nullable()();

  /// Stable key for inline `[@citekey]` citations, assigned the first time
  /// the paper is cited and never changed after (so old notes keep
  /// resolving even if the metadata is later edited).
  TextColumn get citekey => text().nullable()();

  /// The reader's own rating/priority, 1–5 stars; null means unrated.
  IntColumn get rating => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
