import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerto_poz/main.dart';

void main() {
  testWidgets('AlertoPozApp initializes and displays splash loading state', (WidgetTester tester) async {
    await tester.pumpWidget(const AlertoPozApp());
    expect(find.byType(AlertoPozApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
