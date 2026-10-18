import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/trash.dart';

void main() {
  test('purging a marked-up image removes its original and sidecar', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase.inMemoryForTesting();
    final dir = Directory.systemTemp.createTempSync('corplex_markup_purge');
    addTearDown(() {
      db.close();
      dir.deleteSync(recursive: true);
    });
    final original = File('${dir.path}/photo.jpg')..writeAsBytesSync([1]);
    final composite = File('${dir.path}/123_marked.png')..writeAsBytesSync([2]);
    final sidecar = File('${dir.path}/123_marked.markup.json')
      ..writeAsStringSync(
        jsonEncode({'original': original.path, 'sketch': '{}'}),
      );
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            noteId: const Value('n1'),
            type: AttachmentType.image,
            path: Value(composite.path),
          ),
        );
    await trashNote(db, 'n1');
    await purgeTrash(db, all: true);
    expect(composite.existsSync(), isFalse);
    expect(sidecar.existsSync(), isFalse);
    expect(original.existsSync(), isFalse);
  });
}
