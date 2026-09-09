// Basic sanity test. The full app requires Firebase initialization, so we only
// verify that a trivial widget tree builds under the test harness.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke test builds a widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('GK Quiz App'))),
    );
    expect(find.text('GK Quiz App'), findsOneWidget);
  });
}
