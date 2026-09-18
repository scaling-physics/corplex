import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/app.dart';

void main() {
  testWidgets('App launches on Notes tab and can switch to Library', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CorplexApp());

    expect(find.text('No notes yet.\nTap + to capture your first one.'),
        findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.text('Papers you reference in notes will show up here.'),
        findsOneWidget);
  });
}
