import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/attachment_label.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/local_files.dart';
import 'package:corplex/data/tables/attachments_table.dart';

Attachment _a({String? title, String? url, String? path}) => Attachment(
  id: 'a',
  type: AttachmentType.podcast,
  title: title,
  url: url,
  path: path,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('file names become readable titles', () {
    expect(
      titleFromFileName('Audio_Overview_Attention.m4a'),
      'Audio Overview Attention',
    );
    expect(
      titleFromFileName('attention-is-all-you-need.pdf'),
      'attention is all you need',
    );
    expect(
      titleFromFileName('A state-of-the-art review.pdf'),
      'A state-of-the-art review',
    );
    expect(titleFromFileName('/x/y/notes__v2.txt'), 'notes v2');
  });

  test('attachment labels', () {
    expect(
      _a(title: 'Audio_Overview_Attention').label,
      'Audio Overview Attention',
    );
    expect(_a(title: 'My_file and more').label, 'My_file and more');
    expect(_a(url: 'https://x.test/a').label, 'https://x.test/a');
    expect(
      _a(path: '/docs/attachments/1727000000_Lecture_3.m4a').label,
      'Lecture 3',
    );
    expect(_a().label, 'Attachment');
  });
}
