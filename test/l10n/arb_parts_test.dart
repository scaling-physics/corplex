import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corplex/l10n/l10n.dart';

import '../../tool/l10n/arb_parts.dart';

void main() {
  test('the ARB parts are complete and consistent', () {
    final merged = mergeArbParts(Directory('lib/l10n/parts'));
    expect(merged.problems.map((p) => '$p'), isEmpty);
  });

  test('the merged ARB files are current', () {
    final merged = mergeArbParts(Directory('lib/l10n/parts'));
    for (final MapEntry(key: lang, value: arb) in merged.byLanguage.entries) {
      expect(
        File('lib/l10n/app_$lang.arb').readAsStringSync(),
        encodeArb(arb),
        reason: 'run: dart run tool/l10n/build_arb.dart',
      );
    }
  });

  test('placeholders are read from ICU messages', () {
    expect(placeholdersOf('Hello {name}'), {'name'});
    expect(placeholdersOf('{count, plural, =1{1 note} other{{count} notes}}'), {
      'count',
    });
    expect(placeholdersOf("'{literal}' and {x}"), {'x'});
  });

  testWidgets('l10n falls back to English without a delegate', (tester) async {
    late String text;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          text = context.l10n.commonCancel;
          return const SizedBox();
        },
      ),
    );
    expect(text, 'Cancel');
  });
}
