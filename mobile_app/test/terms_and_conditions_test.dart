import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerto_poz/screens/home_screen.dart';
import 'package:alerto_poz/screens/otp_screen.dart';
import 'package:alerto_poz/services/api_service.dart';
import 'package:alerto_poz/services/socket_service.dart';
import 'package:alerto_poz/widgets/terms_and_conditions_modal.dart';

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

  group('ALERTO-POZ Terms and Conditions Modal UI & Controls', () {
    testWidgets(
      'Displays title, subtitle, all 13 sections, Last Updated, and requires scrolling before enabling checkbox and Agree button',
      (WidgetTester tester) async {
        bool acceptedCalled = false;
        bool signOutCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TermsAndConditionsModal(
                termsVersion: 'ALERTO_POZ_TERMS_V1',
                effectiveDate: 'October 29, 2026',
                isSubmitting: false,
                onAccept: () async {
                  acceptedCalled = true;
                },
                onSignOut: () async {
                  signOutCalled = true;
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Verify Title & Subtitle
        expect(find.text('Terms and Conditions'), findsOneWidget);
        expect(
          find.text(
            'Please read and agree to the following terms before using the ALERTO-POZ Emergency Network.',
          ),
          findsOneWidget,
        );
        expect(find.text('ALERTO-POZ Terms and Conditions'), findsOneWidget);

        // Verify initial sections are present
        expect(find.text('1. Acceptance of Terms'), findsOneWidget);
        expect(find.text('2. Accurate Account Information'), findsOneWidget);

        // Verify checkbox is initially unchecked and disabled before scrolling
        Checkbox checkbox = tester.widget<Checkbox>(
          find.byKey(const Key('terms_checkbox')),
        );
        expect(checkbox.value, isFalse);
        expect(checkbox.onChanged, isNull);

        // Verify Agree button is disabled initially
        ElevatedButton agreeBtn = tester.widget<ElevatedButton>(
          find.byKey(const Key('terms_agree_button')),
        );
        expect(agreeBtn.onPressed, isNull);

        // Scroll to the bottom of the agreement content
        final scrollFinder = find.byKey(const Key('terms_scroll_view'));
        await tester.drag(scrollFinder, const Offset(0, -3000));
        await tester.pumpAndSettle();

        // Verify final sections and Last Updated are visible
        expect(find.text('13. Contact and Support'), findsOneWidget);
        expect(find.text('Last Updated: October 29, 2026'), findsOneWidget);

        // Now checkbox should be enabled, but still unchecked
        checkbox = tester.widget<Checkbox>(
          find.byKey(const Key('terms_checkbox')),
        );
        expect(checkbox.onChanged, isNotNull);
        expect(checkbox.value, isFalse);

        // Agree button still disabled until checkbox is checked
        agreeBtn = tester.widget<ElevatedButton>(
          find.byKey(const Key('terms_agree_button')),
        );
        expect(agreeBtn.onPressed, isNull);

        // Tap the checkbox
        await tester.tap(find.byKey(const Key('terms_checkbox')));
        await tester.pump();

        checkbox = tester.widget<Checkbox>(
          find.byKey(const Key('terms_checkbox')),
        );
        expect(checkbox.value, isTrue);

        // Agree button is now enabled
        agreeBtn = tester.widget<ElevatedButton>(
          find.byKey(const Key('terms_agree_button')),
        );
        expect(agreeBtn.onPressed, isNotNull);

        // Tap I Agree and Continue
        await tester.tap(find.byKey(const Key('terms_agree_button')));
        await tester.pump();
        expect(acceptedCalled, isTrue);
        expect(signOutCalled, isFalse);
      },
    );

    testWidgets(
      'Declining does not record consent and shows required message with Sign Out and Exit options',
      (WidgetTester tester) async {
        bool acceptedCalled = false;
        bool signOutCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TermsAndConditionsModal(
                termsVersion: 'ALERTO_POZ_TERMS_V1',
                effectiveDate: 'October 29, 2026',
                isSubmitting: false,
                onAccept: () async {
                  acceptedCalled = true;
                },
                onSignOut: () async {
                  signOutCalled = true;
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Tap Decline
        await tester.tap(find.byKey(const Key('terms_decline_button')));
        await tester.pump();

        expect(acceptedCalled, isFalse);
        expect(find.byKey(const Key('terms_decline_banner')), findsOneWidget);
        expect(
          find.text(
            'Agreement is required to continue using the ALERTO-POZ application.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('terms_sign_out_button')), findsOneWidget);
        expect(find.byKey(const Key('terms_exit_app_button')), findsOneWidget);

        // Tap Sign Out
        await tester.tap(find.byKey(const Key('terms_sign_out_button')));
        await tester.pump();
        expect(signOutCalled, isTrue);
      },
    );
  });

  group('ALERTO-POZ End-to-End Mobile App Acceptance Flows', () {
    testWidgets(
      '1-5: Newly registered user verifies OTP, enters dashboard, sees mandatory Terms popup, cannot use dashboard until accepting, and does not see it again on reopen or re-login',
      (WidgetTester tester) async {
        // Simulate backend state in memory
        final Map<int, String> backendAcceptedVersions = {};
        String serverRequiredVersion = 'ALERTO_POZ_TERMS_V1';

        final mockClient = MockClient((http.Request request) async {
          final path = request.url.path;
          if (path == '/api/auth/verify-otp') {
            return http.Response(
              jsonEncode({
                'success': true,
                'token': 'alerto-session-10-1790000000000',
                'user': {
                  'id': 10,
                  'name': 'Juan Dela Cruz',
                  'phone': '09171234567',
                  'email': 'juan@example.com',
                  'type': 'citizen',
                  'active': 1,
                  'id_verified': true,
                  'verification_status': 'approved',
                },
              }),
              200,
            );
          }
          if (path == '/api/user/terms-status') {
            final acceptedVer = backendAcceptedVersions[10];
            final isAccepted = acceptedVer == serverRequiredVersion;
            return http.Response(
              jsonEncode({
                'success': true,
                'userId': 10,
                'requiredVersion': serverRequiredVersion,
                'privacyVersion': 'ALERTO_POZ_PRIVACY_V1',
                'effectiveDate': 'October 29, 2026',
                'accepted': isAccepted,
                'status': isAccepted ? 'accepted' : 'pending',
                'acceptedVersion': acceptedVer,
                'acceptedAt': isAccepted ? 1790000001000 : null,
              }),
              200,
            );
          }
          if (path == '/api/user/terms-accept') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['accepted'] == true &&
                body['termsVersion'] == serverRequiredVersion) {
              backendAcceptedVersions[10] = serverRequiredVersion;
              return http.Response(
                jsonEncode({
                  'success': true,
                  'userId': 10,
                  'requiredVersion': serverRequiredVersion,
                  'accepted': true,
                  'status': 'accepted',
                  'acceptedVersion': serverRequiredVersion,
                  'acceptedAt': 1790000005000,
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({'success': false, 'error': 'Invalid acceptance'}),
              400,
            );
          }
          if (path == '/api/auth/validate') {
            return http.Response(
              jsonEncode({
                'valid': true,
                'user': {
                  'id': 10,
                  'name': 'Juan Dela Cruz',
                  'phone': '09171234567',
                  'email': 'juan@example.com',
                  'type': 'citizen',
                  'active': 1,
                  'id_verified': true,
                  'verification_status': 'approved',
                },
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
          if (path == '/api/incidents/active') {
            return http.Response(
              jsonEncode({'success': true, 'hasActive': false}),
              200,
            );
          }
          return http.Response(jsonEncode({'success': true}), 200);
        });

        tester.view.physicalSize = const Size(1440, 2560);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await http.runWithClient(() async {
          // Step 1: Newly registered user on OTP Screen verifies code -> ID/account approved -> redirected to HomeScreen
          await tester.pumpWidget(
            const MaterialApp(
              home: OtpScreen(
                identifier: '09171234567',
                otpType: 'registration',
              ),
            ),
          );
          await tester.pump();

          final textFields = find.byType(TextField);
          for (int i = 0; i < 6; i++) {
            await tester.enterText(textFields.at(i), '${i + 1}');
          }
          await tester.pump();

          await tester.tap(find.text('Verify Code'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Step 2: User is on HomeScreen and sees Terms and Conditions popup
          expect(find.byType(HomeScreen), findsOneWidget);
          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsOneWidget,
          );

          // Step 3: User cannot interact with dashboard while modal is displayed
          final absorbPointers = tester
              .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
              .where((w) => w.absorbing);
          expect(absorbPointers.isNotEmpty, isTrue);

          // Scroll and accept
          await tester.drag(
            find.byKey(const Key('terms_scroll_view')),
            const Offset(0, -3000),
          );
          await tester.pump();
          await tester.tap(find.byKey(const Key('terms_checkbox')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('terms_agree_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // Modal is dismissed after server confirms acceptance
          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsNothing,
          );

          // Step 4: User closes and reopens app -> does not see the same version again
          await tester.pumpWidget(
            MaterialApp(key: UniqueKey(), home: const HomeScreen()),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsNothing,
          );

          // Step 5 & 9: User clears app data / reinstalls (SharedPreferences cleared), logs in again -> does not see same accepted version again
          await ApiService.clearSession();
          SharedPreferences.setMockInitialValues({});
          await ApiService.saveSession(
            token: 'alerto-session-10-1790000009000',
            user: {
              'id': 10,
              'name': 'Juan Dela Cruz',
              'phone': '09171234567',
              'active': 1,
            },
          );
          await tester.pumpWidget(
            MaterialApp(key: UniqueKey(), home: const HomeScreen()),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsNothing,
          );

          // Step 10: A new required agreement version triggers the popup again
          serverRequiredVersion = 'ALERTO_POZ_TERMS_V2';
          await tester.pumpWidget(
            MaterialApp(key: UniqueKey(), home: const HomeScreen()),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsOneWidget,
          );
          expect(find.text('Version: ALERTO_POZ_TERMS_V2'), findsOneWidget);
        }, () => mockClient);
      },
    );

    testWidgets(
      '6-8 & 12: Existing user without recorded acceptance or failed/offline API request is not falsely marked as accepted',
      (WidgetTester tester) async {
        bool simulateOffline = true;

        final mockClient = MockClient((http.Request request) async {
          if (simulateOffline) {
            throw Exception('Network unreachable');
          }
          final path = request.url.path;
          if (path == '/api/user/terms-status') {
            return http.Response(
              jsonEncode({
                'success': true,
                'userId': 2,
                'requiredVersion': 'ALERTO_POZ_TERMS_V1',
                'privacyVersion': 'ALERTO_POZ_PRIVACY_V1',
                'effectiveDate': 'October 29, 2026',
                'accepted': false,
                'status': 'pending',
                'acceptedVersion': null,
              }),
              200,
            );
          }
          if (path == '/api/user/terms-accept') {
            return http.Response(
              jsonEncode({'success': false, 'error': 'Server failure'}),
              500,
            );
          }
          return http.Response(jsonEncode({'success': true}), 200);
        });

        await http.runWithClient(() async {
          await ApiService.saveSession(
            token: 'alerto-session-2-1790000000000',
            user: {
              'id': 2,
              'name': 'Existing Citizen',
              'email': 'existing@example.com',
              'active': 1,
            },
          );

          // Offline scenario: status check fails -> modal still shown with error banner, NOT assumed accepted
          await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('terms_error_banner')), findsOneWidget);

          // Now go online, retry status -> existing user without acceptance still sees modal
          simulateOffline = false;
          await tester.tap(find.byKey(const Key('terms_retry_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('terms_error_banner')), findsNothing);

          // Scroll, check, and attempt to accept when server returns 500 -> does NOT close modal or mark accepted
          await tester.drag(
            find.byKey(const Key('terms_scroll_view')),
            const Offset(0, -3000),
          );
          await tester.pump();
          await tester.tap(find.byKey(const Key('terms_checkbox')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('terms_agree_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // Modal stays open and displays error banner
          expect(
            find.byKey(const Key('terms_and_conditions_modal')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('terms_error_banner')), findsOneWidget);
        }, () => mockClient);
      },
    );
  });
}
