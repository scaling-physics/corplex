import 'dart:io';

import 'package:corplex/features/csl/csl_registry.dart';
import 'package:corplex/features/csl/style_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_app.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('csl_de');
    CslRegistry.debugReset();
    CslRegistry.customDirectory = () async => dir;
    CslRegistry.readChoice = () async => null;
    CslRegistry.writeChoice = (_) async {};
    CslRegistry.appLanguage = () => 'en-US';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('style picker and its language list in German', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => pickCitationStyle(context),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Zitierstil'), findsOneWidget);
    expect(find.text('Stil hinzufügen…'), findsOneWidget);
    expect(
      find.text('Zitiersprache: Automatisch (English US)'),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('Zitiersprache:'));
    await tester.pumpAndSettle();
    expect(find.text('Zitiersprache'), findsOneWidget);
    expect(find.text('Deutsch (Österreich)'), findsOneWidget);

    await tester.tap(find.text('Deutsch (Deutschland)'));
    await tester.pumpAndSettle();
    expect(find.text('Zitiersprache: Deutsch (Deutschland)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
