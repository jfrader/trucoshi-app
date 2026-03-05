import 'package:flutter_test/flutter_test.dart';

import 'package:trucoshi_app/app/app.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const TrucoshiApp());
    await tester.pumpAndSettle();

    // Basic sanity: we rendered *something*.
    expect(find.byType(TrucoshiApp), findsOneWidget);
  });
}
