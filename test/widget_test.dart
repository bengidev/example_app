// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures to the child widgets in the widget tree, read text, and verify that
// the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example_app/main.dart';

void main() {
  testWidgets('TradeIn Demo App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TradeInDemoApp());

    // Verify that the app title is displayed.
    expect(find.text('Device Trade-In'), findsOneWidget);

    // Verify that the start diagnostics button is present.
    expect(find.text('Start Diagnostics'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Verify that the button is tappable.
    await tester.tap(find.text('Start Diagnostics'));
    await tester.pump();
  });
}
