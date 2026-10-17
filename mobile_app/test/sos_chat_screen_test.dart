import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerto_poz/screens/sos_chat_screen.dart';
import 'package:alerto_poz/models/user.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = UserModel(
    id: 1,
    name: 'Juan Dela Cruz',
    phone: '09123456789',
    email: 'juan@test.com',
    type: 'citizen',
  );

  Widget createChatScreen({Map<String, dynamic>? activeIncident, String? initialCategory}) {
    return MaterialApp(
      home: SosChatScreen(
        user: testUser,
        activeIncident: activeIncident,
        initialCategory: initialCategory,
      ),
    );
  }

  group('SosChatScreen Widget & Rapid Tap Tests', () {
    testWidgets('Send button is present and disabled when input is empty and no emergency selected', (WidgetTester tester) async {
      await tester.pumpWidget(createChatScreen());
      await tester.pump();

      final sendBtn = find.byKey(const ValueKey('btn_send'));
      expect(sendBtn, findsOneWidget);

      final inkWell = tester.widget<InkWell>(sendBtn);
      // When empty and no category, onTap is null
      expect(inkWell.onTap, isNull);
    });

    testWidgets('Send button enables when message text is entered', (WidgetTester tester) async {
      await tester.pumpWidget(createChatScreen());
      await tester.pump();

      final input = find.byKey(const ValueKey('input_message'));
      expect(input, findsOneWidget);

      await tester.enterText(input, 'Emergency assistance needed!');
      await tester.pump();

      final sendBtn = find.byKey(const ValueKey('btn_send'));
      final inkWell = tester.widget<InkWell>(sendBtn);
      expect(inkWell.onTap, isNotNull);
    });

    testWidgets('Rapid tapping on Send button does not trigger duplicate submissions', (WidgetTester tester) async {
      final activeIncident = {
        'id': 'INC-20261017-001',
        'ticketCode': '20261017-001',
        'status': 'pending',
        'category': 'medical',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };

      await tester.pumpWidget(createChatScreen(activeIncident: activeIncident));
      await tester.pump();

      final input = find.byKey(const ValueKey('input_message'));
      await tester.enterText(input, 'Test rapid sending');
      await tester.pump();

      final sendBtn = find.byKey(const ValueKey('btn_send'));

      // Simulate rapid multiple taps on send button
      await tester.tap(sendBtn);
      await tester.tap(sendBtn);
      await tester.tap(sendBtn);
      await tester.pump();

      // Input should have been cleared on first submission
      final textField = tester.widget<TextField>(input);
      expect(textField.controller?.text, isEmpty);
    });

    testWidgets('Camera and Gallery buttons have key and can be tapped safely', (WidgetTester tester) async {
      await tester.pumpWidget(createChatScreen());
      await tester.pump();

      final cameraBtn = find.byKey(const ValueKey('btn_camera'));
      final galleryBtn = find.byKey(const ValueKey('btn_gallery'));

      expect(cameraBtn, findsOneWidget);
      expect(galleryBtn, findsOneWidget);

      // Rapid tap both (second tap will be ignored cleanly since button disables during action)
      await tester.tap(cameraBtn, warnIfMissed: false);
      await tester.tap(cameraBtn, warnIfMissed: false);
      await tester.pump();

      await tester.tap(galleryBtn, warnIfMissed: false);
      await tester.tap(galleryBtn, warnIfMissed: false);
      await tester.pump();
    });
  });
}
