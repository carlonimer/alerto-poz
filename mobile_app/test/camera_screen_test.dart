import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerto_poz/screens/camera_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraScreen Widget Tests', () {
    testWidgets('CameraScreen default initialMode is 1 (Photo mode)', (WidgetTester tester) async {
      const cameraScreen = CameraScreen();
      expect(cameraScreen.initialMode, equals(1));
    });

    testWidgets('CameraScreen accepts initialMode = 2 (Video mode)', (WidgetTester tester) async {
      const cameraScreen = CameraScreen(initialMode: 2);
      expect(cameraScreen.initialMode, equals(2));
    });

    testWidgets('CameraScreen displays loading spinner initially before camera initializes', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CameraScreen(),
        ),
      );

      // Verify that initial loading state shows a CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
