import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerto_poz/main.dart';
import 'package:alerto_poz/screens/register_screen.dart';
import 'package:alerto_poz/screens/otp_screen.dart';
import 'package:alerto_poz/screens/login_screen.dart';
import 'package:alerto_poz/screens/home_screen.dart';
import 'package:alerto_poz/screens/id_verification_screen.dart';
import 'package:alerto_poz/services/api_service.dart';
import 'package:alerto_poz/services/socket_service.dart';

/// Minimal valid 1x1 PNG bytes (with PNG magic bytes 89 50 4E 47)
final Uint8List kValidPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Minimal valid JPEG header bytes (with JPEG magic bytes FF D8 FF)
final Uint8List kValidJpgBytes = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
  0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
  0x00, 0x48, 0x00, 0x00, 0xFF, 0xD9,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SocketService.disableConnectionForTesting = true;
  });

  tearDown(() {
    SocketService.disconnect();
    SocketService.disableConnectionForTesting = false;
  });

  group('ALERTO-POZ ID Verification Flow & Acceptance Criteria (1-12)', () {
    testWidgets(
      '1-3: Phone registration -> OTP verification -> redirects to ID Verification page (not HomeScreen); repeated for Email registration',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 2800);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        int currentUserId = 101;
        final Map<int, Map<String, dynamic>> users = {};

        final mockClient = MockClient((http.Request request) async {
          final path = request.url.path;
          if (path == '/api/auth/register') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final id = currentUserId++;
            users[id] = {
              'id': id,
              'name': body['name'],
              'phone': body['phone'] ?? '',
              'email': body['email'] ?? '',
              'type': 'citizen',
              'active': 0,
              'id_verified': false,
              'verification_status': 'Unsubmitted',
            };
            return http.Response(
              jsonEncode({'success': true, 'userId': id}),
              200,
            );
          }
          if (path == '/api/auth/verify-otp') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final identifier =
                (body['target'] ?? body['identifier'])?.toString() ?? '';
            final entry = users.values.firstWhere(
              (u) => u['phone'] == identifier || u['email'] == identifier,
              orElse: () => {
                'id': 101,
                'name': 'Test User',
                'phone': identifier,
                'type': 'citizen',
                'active': 1,
                'id_verified': false,
                'verification_status': 'Unsubmitted',
              },
            );
            entry['active'] = 1;
            return http.Response(
              jsonEncode({
                'success': true,
                'token': 'alerto-session-${entry['id']}-1790000000000',
                'user': entry,
              }),
              200,
            );
          }
          if (path == '/api/id-verification/status') {
            return http.Response(
              jsonEncode({
                'success': true,
                'status': 'Unsubmitted',
                'id_verified': false,
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'success': true}), 200);
        });

        await http.runWithClient(() async {
          // --- 1 & 2: Phone Registration -> OTP -> ID Verification Screen ---
          await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
          await tester.pump();

          final regFields = find.byType(TextFormField);
          await tester.enterText(regFields.at(0), 'Maria Santos');
          await tester.enterText(regFields.at(1), '09171112233');
          await tester.enterText(regFields.at(2), 'StrongPass1!');
          await tester.enterText(regFields.at(3), 'StrongPass1!');
          await tester.pump();

          await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Verify OTP Screen opened
          expect(find.byType(OtpScreen), findsOneWidget);

          final otpFields = find.descendant(
            of: find.byType(OtpScreen),
            matching: find.byType(TextField),
          );
          for (int i = 0; i < 6; i++) {
            await tester.enterText(otpFields.at(i), '${i + 1}');
          }
          await tester.pump();

          await tester.tap(find.text('Verify Code'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Confirm ID Verification Screen opens and NOT HomeScreen
          expect(find.byType(IdVerificationScreen), findsOneWidget);
          expect(find.byType(HomeScreen), findsNothing);
          expect(find.text('ID Verification'), findsOneWidget);
          expect(
            find.text(
              'Verify your identity to help keep the Pozorrubio Emergency Network safe and trusted.',
            ),
            findsOneWidget,
          );

          // --- 3: Repeat using Email Registration ---
          await ApiService.clearSession();
          await tester.pumpWidget(
            MaterialApp(key: UniqueKey(), home: const RegisterScreen()),
          );
          await tester.pump();

          // Switch to Email registration method
          await tester.tap(find.text('Email'));
          await tester.pump();

          final emailRegFields = find.byType(TextFormField);
          await tester.enterText(emailRegFields.at(0), 'Carlo Reyes');
          await tester.enterText(emailRegFields.at(1), 'carlo@pozorrubio.ph');
          await tester.enterText(emailRegFields.at(2), 'StrongPass1!');
          await tester.enterText(emailRegFields.at(3), 'StrongPass1!');
          await tester.pump();

          await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(OtpScreen), findsOneWidget);

          final emailOtpFields = find.descendant(
            of: find.byType(OtpScreen),
            matching: find.byType(TextField),
          );
          for (int i = 0; i < 6; i++) {
            await tester.enterText(emailOtpFields.at(i), '${i + 1}');
          }
          await tester.pump();

          await tester.tap(find.text('Verify Code'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(IdVerificationScreen), findsOneWidget);
          expect(find.byType(HomeScreen), findsNothing);
        }, () => mockClient);
      },
    );

    testWidgets(
      '4-7: Dropdown shows all 7 ID types, validates >5MB and invalid formats, requires both front & back images, supports preview/replace/remove, and displays Guidelines card',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 2800);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await ApiService.saveSession(
          token: 'alerto-session-201-1790000000000',
          user: {
            'id': 201,
            'name': 'Pedro Penduko',
            'phone': '09180001111',
            'type': 'citizen',
            'active': 1,
            'id_verified': false,
            'verification_status': 'Unsubmitted',
          },
        );

        SelectedIdFile? nextFrontFile;
        SelectedIdFile? nextBackFile;

        final mockClient = MockClient((http.Request request) async {
          if (request.url.path == '/api/id-verification/status') {
            return http.Response(
              jsonEncode({
                'success': true,
                'status': 'Unsubmitted',
                'id_verified': false,
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'success': true}), 200);
        });

        await http.runWithClient(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: IdVerificationScreen(
                customFilePicker: (bool isFront) async {
                  return isFront ? nextFrontFile : nextBackFile;
                },
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          // Verify Guidelines Card content
          expect(
            find.byKey(const Key('id_verification_guidelines_card')),
            findsOneWidget,
          );
          expect(find.text('② ID Verification Guidelines'), findsOneWidget);
          expect(
            find.text(
              'Make sure the ID is not fake or generated by AI and the image is clear and all details are visible.',
            ),
            findsOneWidget,
          );

          // Verify upload instructions
          expect(
            find.text('Click to upload or drag and drop'),
            findsNWidgets(2),
          );
          expect(find.text('PNG, JPG up to 5MB'), findsNWidgets(2));

          // --- 7a: Attempt submit without selecting ID type ---
          await tester.tap(
            find.byKey(const Key('submit_id_verification_button')),
          );
          await tester.pump();
          expect(
            find.text('Please select a valid ID Type before submitting.'),
            findsOneWidget,
          );

          // --- 4: Open dropdown and confirm all 7 ID types appear ---
          await tester.tap(find.byKey(const Key('id_type_dropdown')));
          await tester.pumpAndSettle();

          const expectedTypes = [
            'Barangay ID',
            'School ID',
            'Passport',
            "Driver's License",
            'SSS',
            "Voter's ID",
            'PhilID (National ID)',
          ];
          for (final typeName in expectedTypes) {
            expect(find.text(typeName), findsWidgets);
          }

          // Select PhilID (National ID)
          await tester.tap(find.text('PhilID (National ID)').last);
          await tester.pumpAndSettle();

          // --- 7b: Attempt submit with missing front image ---
          await tester.tap(
            find.byKey(const Key('submit_id_verification_button')),
          );
          await tester.pump();
          expect(
            find.text('Please upload your ID Front Side image.'),
            findsOneWidget,
          );

          // --- 6a: Reject unsupported format (.pdf) ---
          nextFrontFile = SelectedIdFile(
            bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
            fileName: 'document.pdf',
            sizeBytes: 1024,
          );
          await tester.tap(find.byKey(const Key('upload_front_id_box')));
          await tester.pump();
          expect(
            find.text(
              'Invalid file type for ID Front Side. Only PNG and JPG/JPEG images are accepted.',
            ),
            findsOneWidget,
          );

          // --- 6b: Reject file larger than 5 MB ---
          nextFrontFile = SelectedIdFile(
            bytes: kValidPngBytes,
            fileName: 'huge_front.png',
            sizeBytes: 6 * 1024 * 1024, // 6 MB
          );
          await tester.tap(find.byKey(const Key('upload_front_id_box')));
          await tester.pump();
          expect(
            find.text(
              'ID Front Side image exceeds the 5MB maximum file size limit.',
            ),
            findsOneWidget,
          );

          // --- 5a: Upload valid Front PNG image ---
          nextFrontFile = SelectedIdFile(
            bytes: kValidPngBytes,
            fileName: 'philid_front.png',
            sizeBytes: kValidPngBytes.length,
          );
          await tester.tap(find.byKey(const Key('upload_front_id_box')));
          await tester.pump();
          expect(find.textContaining('philid_front.png'), findsOneWidget);
          expect(
            find.byKey(const Key('replace_front_id_button')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('remove_front_id_button')),
            findsOneWidget,
          );

          // --- 7c: Attempt submit with missing back image ---
          await tester.tap(
            find.byKey(const Key('submit_id_verification_button')),
          );
          await tester.pump();
          expect(
            find.text('Please upload your ID Back Side image.'),
            findsOneWidget,
          );

          // --- 5b: Upload valid Back JPG image, test remove & re-upload ---
          nextBackFile = SelectedIdFile(
            bytes: kValidJpgBytes,
            fileName: 'philid_back.jpg',
            sizeBytes: kValidJpgBytes.length,
          );
          await tester.tap(find.byKey(const Key('upload_back_id_box')));
          await tester.pump();
          expect(find.textContaining('philid_back.jpg'), findsOneWidget);

          // Remove back image and confirm submission is blocked again
          await tester.tap(find.byKey(const Key('remove_back_id_button')));
          await tester.pump();
          expect(find.textContaining('philid_back.jpg'), findsNothing);
        }, () => mockClient);
      },
    );

    testWidgets(
      '8-12: Submit ID -> Pending confirmation screen -> persists across restart -> blocks dashboard before approval -> Admin Rejects with reason -> User resubmits -> Admin Approves -> Dashboard & login unlocked',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 2800);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        String serverStatus = 'Unsubmitted';
        String? serverIdType;
        String? serverRejectionReason;
        bool serverIdVerified = false;

        Map<String, dynamic> buildUserPayload() => {
              'id': 305,
              'name': 'Elena Cruz',
              'phone': '09192223344',
              'email': 'elena@pozorrubio.ph',
              'type': 'citizen',
              'active': 1,
              'id_verified': serverIdVerified,
              'verification_status': serverStatus,
              'id_verification_status': serverStatus,
              'id_type': serverIdType,
              'rejection_reason': serverRejectionReason,
            };

        await ApiService.saveSession(
          token: 'alerto-session-305-1790000000000',
          user: buildUserPayload(),
        );

        final mockClient = MockClient((http.Request request) async {
          final path = request.url.path;
          if (path == '/api/id-verification/status') {
            return http.Response(
              jsonEncode({
                'success': true,
                'status': serverStatus,
                'id_verified': serverIdVerified,
                'id_type': serverIdType,
                'rejection_reason': serverRejectionReason,
                'user': buildUserPayload(),
              }),
              200,
            );
          }
          if (path == '/api/id-verification/submit') {
            serverStatus = 'Pending';
            serverIdVerified = false;
            serverIdType = "Driver's License";
            serverRejectionReason = null;
            return http.Response(
              jsonEncode({
                'success': true,
                'status': 'Pending',
                'id_type': serverIdType,
                'submitted_at': 1790000050000,
                'message':
                    'Your ID has been submitted successfully and is awaiting verification. You will be notified when your verification status changes.',
                'user': buildUserPayload(),
              }),
              200,
            );
          }
          if (path == '/api/auth/validate') {
            return http.Response(
              jsonEncode({
                'valid': true,
                'user': buildUserPayload(),
              }),
              200,
            );
          }
          if (path == '/api/auth/login') {
            return http.Response(
              jsonEncode({
                'token': 'alerto-session-305-1790000090000',
                'user': buildUserPayload(),
              }),
              200,
            );
          }
          if (path == '/api/user/terms-status') {
            return http.Response(
              jsonEncode({
                'success': true,
                'userId': 305,
                'requiredVersion': 'ALERTO_POZ_TERMS_V1',
                'privacyVersion': 'ALERTO_POZ_PRIVACY_V1',
                'effectiveDate': 'October 29, 2026',
                'accepted': true,
                'status': 'accepted',
                'acceptedVersion': 'ALERTO_POZ_TERMS_V1',
              }),
              200,
            );
          }
          if (path == '/api/db-state') {
            return http.Response(
              jsonEncode({
                'incidents': [],
                'responders': [],
                'broadcasts': [],
              }),
              200,
            );
          }
          if (path.startsWith('/api/incidents/active')) {
            return http.Response(
              jsonEncode({'success': true, 'hasActive': false}),
              200,
            );
          }
          return http.Response(jsonEncode({'success': true}), 200);
        });

        await http.runWithClient(() async {
          // --- 8: Select ID Type, upload front & back images, and Submit ---
          await tester.pumpWidget(
            MaterialApp(
              home: IdVerificationScreen(
                customFilePicker: (bool isFront) async {
                  return SelectedIdFile(
                    bytes: isFront ? kValidPngBytes : kValidJpgBytes,
                    fileName: isFront ? 'license_front.png' : 'license_back.jpg',
                    sizeBytes:
                        isFront ? kValidPngBytes.length : kValidJpgBytes.length,
                  );
                },
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          await tester.tap(find.byKey(const Key('id_type_dropdown')));
          await tester.pumpAndSettle();
          await tester.tap(find.text("Driver's License").last);
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('upload_front_id_box')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('upload_back_id_box')));
          await tester.pump();

          await tester.tap(
            find.byKey(const Key('submit_id_verification_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Confirm Pending confirmation view is displayed
          expect(
            find.byKey(const Key('id_verification_pending_view')),
            findsOneWidget,
          );
          expect(find.text('ID Verification Submitted'), findsOneWidget);
          expect(
            find.text(
              'Your ID has been submitted successfully and is awaiting verification. You will be notified when your verification status changes.',
            ),
            findsOneWidget,
          );
          expect(find.text('Pending'), findsOneWidget);

          // --- 9: Restart the app (AuthGate) and verify Pending status persists ---
          await tester.pumpWidget(
            MaterialApp(key: UniqueKey(), home: const AuthGate()),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(IdVerificationScreen), findsOneWidget);
          expect(find.byType(HomeScreen), findsNothing);
          expect(find.text('ID Verification Submitted'), findsOneWidget);
          expect(find.text('Pending'), findsOneWidget);

          // --- 10: Attempt to navigate directly to HomeScreen before approval -> blocked & redirected to IdVerificationScreen ---
          await tester.pumpWidget(
            MaterialApp(key: UniqueKey(), home: const HomeScreen()),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(IdVerificationScreen), findsOneWidget);
          expect(find.byType(HomeScreen), findsNothing);

          // --- 11a: Administrator Rejects with reason ---
          serverStatus = 'Rejected';
          serverIdVerified = false;
          serverRejectionReason = 'Back side of ID is blurry. Please upload a clearer photo.';

          await tester.tap(
            find.byKey(const Key('refresh_verification_status_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Verify Rejection banner & reason are shown and user can resubmit on existing account
          expect(
            find.byKey(const Key('id_verification_rejected_banner')),
            findsOneWidget,
          );
          expect(find.text('Verification Status: Rejected'), findsOneWidget);
          expect(
            find.text(
              'Reason: Back side of ID is blurry. Please upload a clearer photo.',
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('id_verification_form_view')),
            findsOneWidget,
          );

          // --- 11b: Resubmit after rejection ---
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              home: IdVerificationScreen(
                customFilePicker: (bool isFront) async {
                  return SelectedIdFile(
                    bytes: isFront ? kValidPngBytes : kValidJpgBytes,
                    fileName:
                        isFront ? 'clear_front.png' : 'clear_back.jpg',
                    sizeBytes:
                        isFront ? kValidPngBytes.length : kValidJpgBytes.length,
                  );
                },
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          await tester.tap(find.byKey(const Key('upload_front_id_box')));
          await tester.pump();
          await tester.ensureVisible(
            find.byKey(const Key('upload_back_id_box')),
          );
          await tester.tap(find.byKey(const Key('upload_back_id_box')));
          await tester.pump();
          await tester.ensureVisible(
            find.byKey(const Key('submit_id_verification_button')),
          );
          await tester.tap(
            find.byKey(const Key('submit_id_verification_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('ID Verification Submitted'), findsOneWidget);
          expect(find.text('Pending'), findsOneWidget);

          // --- 11c & 12: Administrator Approves -> User checks status -> Redirected to HomeScreen (Dashboard) ---
          serverStatus = 'Approved';
          serverIdVerified = true;
          serverRejectionReason = null;

          await tester.tap(
            find.byKey(const Key('refresh_verification_status_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(HomeScreen), findsOneWidget);
          expect(find.text('ALERTO -POZ'), findsOneWidget);

          // Verify login flow also goes directly to HomeScreen once Approved
          await tester.pumpWidget(
            MaterialApp(key: UniqueKey(), home: const LoginScreen()),
          );
          await tester.pump();
          final loginFields = find.byType(TextFormField);
          await tester.enterText(loginFields.at(0), '09192223344');
          await tester.enterText(loginFields.at(1), 'StrongPass1!');
          await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(HomeScreen), findsOneWidget);
        }, () => mockClient);
      },
    );
  });
}
