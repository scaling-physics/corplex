import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:corplex/features/notes/note_bibliography.dart';

void main() {
  late AppDatabase db;
  late QuillController controller;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('a'),
            title: 'Alpha',
            authors: const Value('Smith, Jo'),
            year: const Value(2020),
            citekey: const Value('smith2020'),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('b'),
            title: 'Beta',
            authors: const Value('Adams, Bo'),
            year: const Value(2019),
            citekey: const Value('adams2019'),
          ),
        );
    controller = QuillController.basic();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  void write(String text) => controller.replaceText(0, 0, text, null);

  test('appends a References heading and one line per cited paper', () async {
    write('Claims [@smith2020] and [@adams2019].');
    expect(await insertBibliography(controller, db, CitationStyle.apa), 2);

    final text = controller.document.toPlainText();
    expect(text, contains('.\n\nReferences\n'), reason: 'a blank line before');
    expect(
      text.indexOf('Adams'),
      lessThan(text.indexOf('Smith, J. (2020)')),
      reason: 'alphabetical',
    );
    expect(bibliographyStart(controller.document.toDelta()), isNotNull);
  });

  test('regenerating replaces the old list instead of stacking', () async {
    write('One [@smith2020].');
    await insertBibliography(controller, db, CitationStyle.apa);
    controller.replaceText(0, 0, 'Also [@adams2019]. ', null);
    await insertBibliography(controller, db, CitationStyle.mla);

    final text = controller.document.toPlainText();
    expect('References'.allMatches(text), hasLength(1));
    expect(text, contains('Adams'));
    expect(text, contains('"Alpha."'), reason: 'now MLA');
    expect(
      text.trim().split('\n').where((l) => l.contains('Smith')),
      hasLength(1),
      reason: 'one reference, not stacked',
    );
  });

  test('a note without known citations is left alone', () async {
    write('Nothing to cite [@unknown].');
    final before = controller.document.toPlainText();
    expect(await insertBibliography(controller, db, CitationStyle.apa), 0);
    expect(controller.document.toPlainText(), before);
  });
}
