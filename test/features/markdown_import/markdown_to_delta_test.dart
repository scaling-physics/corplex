import 'dart:convert';

import 'package:corplex/features/markdown_import/markdown_to_delta.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_highlight.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/features/notes/note_table.dart';
import 'package:flutter_test/flutter_test.dart';

class _Resolver implements MdResolver {
  _Resolver({
    this.notes = const {},
    this.files = const {},
    this.blocks = const {},
  });
  final Map<String, MdNoteRef> notes;
  final Map<String, String> files;
  final Map<String, String> blocks;

  @override
  MdNoteRef? note(String target) {
    var t = target.toLowerCase();
    if (t.endsWith('.md')) t = t.substring(0, t.length - 3);
    return notes[t];
  }

  @override
  String? file(String target) => files[target];

  @override
  String? blockPreview(String noteId, String blockId) =>
      blocks['$noteId/$blockId'];
}

MdConversion md(
  String text, {
  MdResolver? resolver,
  String title = 'T',
  String? selfId,
}) => markdownToDelta(
  text,
  resolver: resolver ?? const NoResolver(),
  fileTitle: title,
  selfId: selfId,
);

/// One string per line: `[attrs] text`, embeds as `<type>`.
List<String> lines(MdConversion c) {
  final out = <String>[];
  var text = StringBuffer();
  for (final op in c.ops) {
    final ins = op['insert'];
    if (ins is Map) {
      text.write('<${ins.keys.first}>');
      continue;
    }
    final parts = (ins as String).split('\n');
    for (var i = 0; i < parts.length; i++) {
      text.write(parts[i]);
      if (i < parts.length - 1) {
        final a = op['attributes'] as Map?;
        final prefix = a == null
            ? ''
            : a.entries.map((e) => '${e.key}=${e.value}').join(',');
        out.add(prefix.isEmpty ? '$text' : '[$prefix] $text');
        text = StringBuffer();
      }
    }
  }
  return out;
}

Map<String, dynamic>? attrsOf(MdConversion c, String text) {
  for (final op in c.ops) {
    if (op['insert'] == text) return op['attributes'] as Map<String, dynamic>?;
  }
  fail('no op "$text" in ${c.ops}');
}

void main() {
  group('front matter', () {
    test('tags and aliases as lists, flow lists and strings', () {
      final a = splitFrontmatter(
        '---\ntags:\n  - a\n  - "b c"\naliases: [X, "Y Z"]\n---\nbody',
      );
      expect(a.frontmatter.tags, ['a', 'b c']);
      expect(a.frontmatter.aliases, ['X', 'Y Z']);
      expect(a.body.trim(), 'body');
      final b = splitFrontmatter(
        '---\ntags: #one, two three\nalias: Single\n---\nx',
      );
      expect(b.frontmatter.tags, ['one', 'two', 'three']);
      expect(b.frontmatter.aliases, ['Single']);
    });

    test('flags, dates, CRLF, BOM and unterminated blocks', () {
      final f = splitFrontmatter(
        '﻿---\r\nlocked: true\r\ncitekey: "k"\r\ncreated: 2026-01-02T03:04:05Z\r\n---\r\nhello',
      );
      expect(f.frontmatter.locked, isTrue);
      expect(f.frontmatter.citekey, 'k');
      expect(f.frontmatter.created, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(f.body, 'hello');
      final open = splitFrontmatter('---\nnot closed\ntext');
      expect(open.frontmatter.tags, isEmpty);
      expect(open.body, startsWith('---'));
      // An hr later in the file is not front matter.
      expect(
        splitFrontmatter('text\n---\na: b\n---\n').frontmatter.fields,
        isEmpty,
      );
    });

    test('empty values, comments, quotes and block scalars', () {
      final f = splitFrontmatter(
        "---\n# comment\ntags:\naliases: []\ntitle: 'it''s'\nsummary: |\n  line1\n  line2\n---\n",
      );
      expect(f.frontmatter.tags, isEmpty);
      expect(f.frontmatter.aliases, isEmpty);
      expect(f.frontmatter.fields['title'], "it's");
      expect(f.frontmatter.fields['summary'], 'line1\nline2');
    });
  });

  group('title', () {
    test('a leading heading equal to the file name is dropped', () {
      final c = md('# My Note\n\nBody', title: 'My Note');
      expect(c.title, 'My Note');
      expect(lines(c), ['Body']);
    });

    test('compares by file-name rules, keeping the real title', () {
      final c = md('# Why: a question?\n\nx', title: 'Why a question');
      expect(c.title, 'Why: a question?');
      expect(lines(c), ['x']);
    });

    test('a different heading stays in the body', () {
      final c = md('# Other\n\nx', title: 'My Note');
      expect(c.title, 'My Note');
      expect(lines(c), ['[header=1] Other', 'x']);
    });

    test('front matter before the title', () {
      final c = md('---\ntags: [a]\n---\n\n# Hi\ntext', title: 'Hi');
      expect(lines(c), ['text']);
    });
  });

  group('blocks', () {
    test('headings shift down one level like the exporter writes them', () {
      final c = md('## A\n### B\n#### C\n##### D\n###### E', title: 'T');
      expect(lines(c), [
        '[header=1] A',
        '[header=2] B',
        '[header=3] C',
        '[header=3] D',
        '[header=3] E',
      ]);
    });

    test('closing hashes and #tag without a space', () {
      final c = md('## Title ##\n#notaheading here');
      expect(lines(c), ['[header=1] Title', '#notaheading here']);
      expect(c.tags, {'notaheading'});
    });

    test('lists, nesting, ordered, checklists', () {
      final c = md(
        '- a\n  - b\n    - c\n- d\n\n1. one\n2. two\n\n- [ ] todo\n- [x] done\n  * [X] sub',
      );
      expect(lines(c), [
        '[list=bullet] a',
        '[list=bullet,indent=1] b',
        '[list=bullet,indent=2] c',
        '[list=bullet] d',
        '[list=ordered] one',
        '[list=ordered] two',
        '[list=unchecked] todo',
        '[list=checked] done',
        '[list=checked,indent=1] sub',
      ]);
    });

    test('tab-indented and 4-space nested lists, ordered with parens', () {
      final c = md('- a\n\t- b\n1) x\n    2) y');
      expect(lines(c), [
        '[list=bullet] a',
        '[list=bullet,indent=1] b',
        '[list=ordered] x',
        '[list=ordered,indent=1] y',
      ]);
    });

    test('a number that is not a list stays text', () {
      expect(lines(md('1.5 million')), ['1.5 million']);
      expect(lines(md('**Bold** start')), ['Bold start']);
    });

    test('block quotes and callouts stay quote text', () {
      final c = md('> a quote\n>> deeper\n\n> [!warning] Careful\n> body');
      expect(lines(c), [
        '[blockquote=true] a quote',
        '[blockquote=true] deeper',
        '[blockquote=true] [!warning] Careful',
        '[blockquote=true] body',
      ]);
    });

    test('fenced code becomes code-block lines, markup untouched', () {
      final c = md('before\n```dart\nvar **x** = 1;\n\n  indented\n```\nafter');
      expect(lines(c), [
        'before',
        '[code-block=true] var **x** = 1;',
        '[code-block=true] ',
        '[code-block=true]   indented',
        'after',
      ]);
      final tilde = md('~~~\nx\n~~~');
      expect(lines(tilde), ['[code-block=true] x']);
    });

    test('an unclosed fence runs to the end', () {
      expect(lines(md('```\na\nb')), [
        '[code-block=true] a',
        '[code-block=true] b',
      ]);
    });

    test('horizontal rules and blank lines vanish', () {
      expect(lines(md('a\n\n---\n\n***\n\nb')), ['a', 'b']);
    });

    test('CRLF and unicode', () {
      final c = md('# Ünï\r\n\r\nzwei Zeilen\r\nnoch 日本語 😀\r\n', title: 'Ünï');
      expect(lines(c), ['zwei Zeilen', 'noch 日本語 😀']);
    });

    test('an empty document is one newline', () {
      final c = md('');
      expect(c.ops, [
        {'insert': '\n'},
      ]);
      expect(decodeNoteContent(c.content).toPlainText(), '\n');
    });

    test('%% comments %% and html comments are dropped, code kept', () {
      final c = md(
        'a %%hidden%% b\n%%\nmulti\n%%\n<!-- x -->\n```\n%% keep %%\n```',
      );
      expect(lines(c), ['a  b', '[code-block=true] %% keep %%']);
    });
  });

  group('inline formatting', () {
    test('bold, italic, strike, code, highlight', () {
      final c = md('**b** *i* _i2_ __b2__ ~~s~~ `c` ==h== ***both***');
      expect(attrsOf(c, 'b'), {'bold': true});
      expect(attrsOf(c, 'i'), {'italic': true});
      expect(attrsOf(c, 'i2'), {'italic': true});
      expect(attrsOf(c, 'b2'), {'bold': true});
      expect(attrsOf(c, 's'), {'strike': true});
      expect(attrsOf(c, 'c'), {'code': true});
      expect(attrsOf(c, 'h'), {'background': NoteHighlight.yellow.hex});
      expect(attrsOf(c, 'both'), {'bold': true, 'italic': true});
    });

    test('nested emphasis', () {
      final c = md('**bold and *both* here**');
      expect(attrsOf(c, 'bold and '), {'bold': true});
      expect(attrsOf(c, 'both'), {'bold': true, 'italic': true});
    });

    test('snake_case and stray markers stay text', () {
      expect(lines(md('snake_case_name and 2 * 3 * 4 and a_b')), [
        'snake_case_name and 2 * 3 * 4 and a_b',
      ]);
      expect(lines(md('**unclosed and ==x')), ['**unclosed and ==x']);
    });

    test('escapes', () {
      expect(lines(md(r'\*not italic\* and \[x\]')), ['*not italic* and [x]']);
    });

    test('code spans protect their content', () {
      final c = md('`**no** [[link]] \$x\$`');
      expect(attrsOf(c, '**no** [[link]] \$x\$'), {'code': true});
      final dbl = md('`` a`b ``');
      expect(attrsOf(dbl, 'a`b'), {'code': true});
    });

    test('maths stays text and protects underscores', () {
      final c = md(r'Let $a_b * c_d$ be and $$ \int f $$ too, cost $5 and $10');
      expect(
        lines(c).single,
        r'Let $a_b * c_d$ be and $$ \int f $$ too, cost $5 and $10',
      );
    });

    test('display maths across lines folds into one paragraph', () {
      final c = md('before\n\$\$\nx = y\n+ z\n\$\$\nafter');
      expect(lines(c), ['before', r'$$ x = y + z $$', 'after']);
      expect(lines(md(r'$$ a $$')), [r'$$ a $$']);
    });

    test('citations and block ids stay text', () {
      final c = md('Per [@smith2020, p. 4; @lee19] this holds. ^abc-1');
      expect(
        lines(c).single,
        'Per [@smith2020, p. 4; @lee19] this holds. ^abc-1',
      );
    });

    test('inline tags are collected and kept', () {
      final c = md('Tags #a #b/c #2024 (#paren) not#this url/#frag');
      expect(c.tags, {'a', 'b/c', 'paren'});
      expect(lines(c).single, contains('#a #b/c'));
    });

    test('br becomes a line break', () {
      expect(lines(md('a<br>b<br/>c')), ['a', 'b', 'c']);
    });
  });

  group('footnotes', () {
    test('references with definitions become inline notes', () {
      final c = md(
        'Text[^1] and more[^note].\n\n[^1]: First **note**.\n[^note]: Second\n    continued.',
      );
      expect(lines(c), ['Text^[First note.] and more^[Second continued.].']);
    });

    test('keeps citations and maths in the note, undefined refs stay', () {
      final c = md(
        r'A[^a] B[^zz]'
        '\n\n'
        r'[^a]: See [@k] and $x^2$.',
      );
      expect(lines(c).single, r'A^[See [@k] and $x^2$.] B[^zz]');
    });

    test('unbalanced brackets in a note are made safe', () {
      final c = md('A[^a]\n\n[^a]: oops ] odd [ here');
      expect(lines(c).single, 'A^[oops ) odd ( here]');
    });

    test('an existing inline footnote is kept', () {
      expect(
        lines(md('A^[inline [@k] note] B')).single,
        'A^[inline [@k] note] B',
      );
    });
  });

  group('tables', () {
    test('pipe tables become table embeds', () {
      final c = md(
        '| A | B |\n|---|:-:|\n| 1 | **two** |\n| x \\| y | `z` |\nafter',
      );
      expect(lines(c), ['<table>', 'after']);
      final json = (c.ops.first['insert'] as Map)['table'] as String;
      final t = NoteTable.decode(json);
      expect(t.header, isTrue);
      expect(t.rows, [
        ['A', 'B'],
        ['1', 'two'],
        ['x | y', 'z'],
      ]);
    });

    test('an empty header row means no header; br in cells', () {
      final c = md('|  |  |\n| --- | --- |\n| a<br>b | c |');
      final t = NoteTable.decode(
        (c.ops.first['insert'] as Map)['table'] as String,
      );
      expect(t.header, isFalse);
      expect(t.rows, [
        ['a\nb', 'c'],
      ]);
    });

    test('a pipe in prose is not a table', () {
      expect(lines(md('a | b\nc')), ['a | b', 'c']);
    });

    test('ragged rows are padded; documents survive decode', () {
      final c = md('a|b|c\n-|-|-\n1|2');
      final t = NoteTable.decode(
        (c.ops.first['insert'] as Map)['table'] as String,
      );
      expect(t.rows.last, ['1', '2', '']);
      expect(decodeNoteContent(c.content).toPlainText(), isNotEmpty);
    });
  });

  group('links', () {
    final alpha = const MdNoteRef('id-alpha', 'Alpha');
    final resolver = _Resolver(
      notes: {
        'alpha': alpha,
        'beta': const MdNoteRef('id-beta', 'Beta'),
        'projects/beta': const MdNoteRef('id-beta', 'Beta'),
      },
      files: {'img.png': 'assets/img.png', 'doc.pdf': 'files/doc.pdf'},
      blocks: {'id-beta/b1': 'Beta paragraph text'},
    );

    test('wiki links, aliases, headings and blocks', () {
      final c = md(
        '[[Alpha]] [[Alpha|the first]] [[Alpha#Goals]] [[Beta#^b1]] [[Beta#^nope]] [[Projects/Beta]]',
        resolver: resolver,
      );
      final links = [
        for (final op in c.ops)
          if (op['attributes'] is Map &&
              (op['attributes'] as Map)['link'] != null)
            (
              op['insert'] as String,
              (op['attributes'] as Map)['link'] as String,
            ),
      ];
      expect(links, [
        ('Alpha', noteLink('id-alpha')),
        ('the first', noteLink('id-alpha')),
        ('Alpha › Goals', noteLink('id-alpha', heading: 'Goals')),
        ('Beta › Beta paragraph text', noteLink('id-beta', block: 'b1')),
        ('Beta', noteLink('id-beta', block: 'nope')),
        ('Beta', noteLink('id-beta')),
      ]);
      expect(c.unresolved, 0);
    });

    test('heading with spaces and unicode round-trips through the link', () {
      final c = md('[[Alpha#Größe der Welt]]', resolver: resolver);
      final link = (c.ops.first['attributes'] as Map)['link'] as String;
      expect(parseNoteLinkTarget(link)!.heading, 'Größe der Welt');
    });

    test('nested heading path uses the last segment', () {
      final c = md('[[Alpha#One#Two]]', resolver: resolver);
      final link = (c.ops.first['attributes'] as Map)['link'] as String;
      expect(parseNoteLinkTarget(link)!.heading, 'Two');
    });

    test('links to the note itself', () {
      final c = md(
        '[[#Intro]] [[#^blk]]',
        resolver: resolver,
        selfId: 'me',
        title: 'Me',
      );
      final first = (c.ops.first['attributes'] as Map)['link'] as String;
      expect(
        parseNoteLinkTarget(first),
        const NoteLinkTarget('me', heading: 'Intro'),
      );
      expect(c.unresolved, 0);
    });

    test('unresolved links stay text and are counted', () {
      final c = md(
        '[[Nope]] [[Nope|shown]] [[Nope#H]] ![[Nope]]',
        resolver: resolver,
      );
      expect(lines(c).single, 'Nope shown Nope › H Nope');
      expect(c.unresolved, 4);
      expect(
        c.ops.every(
          (o) =>
              o['attributes'] == null ||
              (o['attributes'] as Map)['link'] == null,
        ),
        isTrue,
      );
    });

    test('markdown links to notes, with fragments and encoding', () {
      final c = md(
        '[go](Alpha.md) [h](Alpha.md#Goals) [e](Alpha%20x.md) [web](https://x.org/a_b) [mail](mailto:a@b.c) [t](#Top)',
        resolver: resolver,
        selfId: 'me',
        title: 'Me',
      );
      final links = {
        for (final op in c.ops)
          if (op['attributes'] is Map &&
              (op['attributes'] as Map)['link'] != null)
            op['insert'] as String: (op['attributes'] as Map)['link'] as String,
      };
      expect(links['go'], noteLink('id-alpha'));
      expect(links['h'], noteLink('id-alpha', heading: 'Goals'));
      expect(links['web'], 'https://x.org/a_b');
      expect(links['mail'], 'mailto:a@b.c');
      expect(links['t'], noteLink('me', heading: 'Top'));
      expect(c.unresolved, 1); // Alpha x.md
    });

    test('formatting inside link text', () {
      final c = md('[**bold** link](https://x.org)');
      expect(attrsOf(c, 'bold'), {'bold': true, 'link': 'https://x.org'});
    });

    test('embeds on their own line are cards, inline they are links', () {
      final c = md(
        '![[Alpha]]\n![[Alpha#Goals]]\nSee ![[Beta]] here',
        resolver: resolver,
      );
      expect(lines(c), ['<noteembed>', '<noteembed>', 'See Beta here']);
      final embed = (c.ops.first['insert'] as Map)['noteembed'] as String;
      expect(noteEmbedLink(embed), noteLink('id-alpha'));
      final second = (c.ops[2]['insert'] as Map)['noteembed'] as String;
      expect(noteEmbedLink(second), noteLink('id-alpha', heading: 'Goals'));
    });

    test('image and file embeds become attachments and vanish', () {
      final c = md(
        'Text\n\n![[img.png]]\n![alt](img.png)\n[[doc.pdf]]\n[the doc](doc.pdf) after\nmid ![[img.png|300]] line',
        resolver: resolver,
      );
      expect(c.attachments, ['assets/img.png', 'files/doc.pdf']);
      expect(lines(c), ['Text', 'the doc after', 'mid  line']);
      expect(c.unresolved, 0);
    });

    test('missing images stay as their alt text', () {
      final c = md('![a pic](gone.png) ![[gone2.png]]', resolver: resolver);
      expect(lines(c).single, 'a pic gone2.png');
      expect(c.unresolved, 2);
    });

    test('remote and data images', () {
      final c = md(
        '![logo](https://x.org/l.png) ![d](data:image/svg+xml;base64,AAAA)',
      );
      expect(attrsOf(c, 'logo'), {'link': 'https://x.org/l.png'});
      expect(lines(c).single, 'logo ');
    });

    test('a trailing empty Attachments heading is removed', () {
      final c = md(
        'Body\n\n## Attachments\n\n![[img.png]]\n\n[[doc.pdf]]',
        resolver: resolver,
      );
      expect(lines(c), ['Body']);
    });

    test('Corplex citations written as wiki links come back', () {
      final c = md(
        'See [[@smith2020 A study|@smith2020]], p. 42 and [[@lee19 Other|@lee19]]; [[@smith2020 A study|— p. 4]]',
      );
      expect(lines(c).single, 'See [@smith2020, p. 42] and [@lee19]; — p. 4');
    });
  });

  group('a whole document survives decoding', () {
    test('mixed content decodes into a Quill document', () {
      final c = md(
        '# T\n\n## H\n\ntext **b**\n\n- [ ] x\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```\ncode\n```\n',
      );
      final doc = decodeNoteContent(c.content);
      expect(doc.toPlainText(), contains('text b'));
      expect(jsonDecode(c.content), isA<List>());
      expect(c.plainText, doc.toPlainText().replaceAll('￼', '￼'));
    });
  });
}
