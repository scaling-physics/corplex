import 'dart:io';

import 'package:corplex/features/csl/csl_engine.dart';
import 'package:corplex/features/csl/csl_processor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'csl_support.dart';

/// Collapse marks dates with private-use characters while it works; none
/// may reach a citation or reference entry, in any bundled style.
void main() {
  final styles = Directory('assets/csl')
      .listSync()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.csl'))
      .map((n) => n.substring(0, n.length - 4))
      .toList();

  final items = [
    vaswani,
    journal,
    paper('s1', 'article-journal', 'First', [
      person('Smith', 'Ann'),
    ], year: 2019),
    paper('s2', 'article-journal', 'Second', [
      person('Smith', 'Ann'),
    ], year: 2019),
  ];

  for (final style in styles) {
    test('$style leaves no date markers', () {
      final out = processorFor(style).process(
        items,
        cites: [
          [const CslCite(0)],
          [const CslCite(2), const CslCite(3), const CslCite(1)],
          [const CslCite(2, locator: '42'), const CslCite(3)],
        ],
      );
      for (final r in [...out.citations, ...out.bibliography]) {
        expect(r.plain, isNot(contains(cslDateStart)), reason: '$r');
        expect(r.plain, isNot(contains(cslDateEnd)), reason: '$r');
      }
    });
  }
}
