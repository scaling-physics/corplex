import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/ink/ink_tools.dart';
import 'package:corplex/l10n/l10n.dart';

import '../support/l10n_app.dart';

void main() {
  testWidgets('the pen toolbar fits a 360 px phone in German', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tools = InkTools();
    // Mirrors the inline toolbar's pinned end (menu + Done).
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => InkPalette(
                tools: tools,
                trailing: [
                  IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: context.l10n.commonUndo,
                    onPressed: () {},
                  ),
                ],
                end: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: context.l10n.inkMoreOptions,
                      icon: const Icon(Icons.more_horiz),
                      itemBuilder: (_) => const [],
                    ),
                    FilledButton.tonal(
                      onPressed: () {},
                      child: Text(context.l10n.commonDone),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Fertig'), findsOneWidget);
    expect(find.byTooltip('Stift'), findsOneWidget);
    expect(find.byTooltip('Textmarker'), findsOneWidget);
    expect(find.byTooltip('Radierer'), findsOneWidget);
    expect(find.byTooltip('Widerrufen'), findsOneWidget);
    expect(find.byTooltip('Weitere Zeichenoptionen'), findsOneWidget);
    tools.dispose();
  });

  test('ink strings are translated', () {
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.inkMoreSpace, 'Mehr Platz');
    expect(de.inkTapToDraw, 'Zum Zeichnen tippen');
    expect(de.markupMarkUp, 'Anmerken');
  });
}
