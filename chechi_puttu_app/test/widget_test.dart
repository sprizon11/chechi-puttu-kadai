// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.
//
// Renders LoginScreen directly rather than ChechiPuttuApp: the full app calls
// Firebase.initializeApp before it can reach a login screen, which throws with
// no Firebase App in the test environment. LoginScreen itself only touches
// Firebase inside its button handlers, never in initState/build, so it is
// safe to pump on its own.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chechi_puttu_app/main.dart';

void main() {
  testWidgets('Login screen boots smoke test', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(isDark: false, onToggleTheme: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}
