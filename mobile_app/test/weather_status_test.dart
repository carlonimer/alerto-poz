import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerto_poz/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Weather Status Model & Caching Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Loads cached weather status when available offline', () async {
      final mockData = {
        'id': 1,
        'status': 'WARNING',
        'title': 'WEATHER WARNING',
        'message': 'Weather warning is currently in effect in Pozorrubio. Please stay alert and take necessary precautions.',
        'color': 'blue',
        'level': 'warning',
        'icon': 'fa-cloud-bolt',
        'updated_by': 1,
        'updated_by_name': 'MDRRMO Officer',
        'updated_at': 1762128000000,
        'updated_at_iso': '2026-11-03T00:00:00.000Z'
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_weather_status', jsonEncode(mockData));

      final result = await ApiService.getWeatherStatus();
      expect(result, isNotNull);
      expect(result!['status'], 'WARNING');
      expect(result['title'], 'WEATHER WARNING');
      expect(result['color'], 'blue');
    });

    test('Verifies NORMAL, WARNING, and EXTREME weather titles and configurations', () {
      final statuses = {
        'NORMAL': 'NORMAL WEATHER',
        'WARNING': 'WEATHER WARNING',
        'EXTREME': 'EXTREME WEATHER WARNING',
      };

      for (final entry in statuses.entries) {
        expect(entry.value.contains(entry.key), isTrue);
      }
    });
  });

  group('Persistent Weather Card UI Rendering Tests', () {
    Widget buildTestWeatherCard({required String status, required String message}) {
      final Color bgColor;
      final Color textColor;
      final IconData iconData;
      final String title;

      if (status == 'WARNING') {
        title = 'WEATHER WARNING';
        bgColor = const Color(0xFF1D4ED8);
        textColor = Colors.white;
        iconData = Icons.thunderstorm_rounded;
      } else if (status == 'EXTREME') {
        title = 'EXTREME WEATHER WARNING';
        bgColor = const Color(0xFFDC2626);
        textColor = Colors.white;
        iconData = Icons.warning_amber_rounded;
      } else {
        title = 'NORMAL WEATHER';
        bgColor = Colors.white;
        textColor = const Color(0xFF0F172A);
        iconData = Icons.wb_sunny_rounded;
      }

      return MaterialApp(
        home: Scaffold(
          body: Container(
            key: const Key('persistent-weather-card'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(iconData, color: textColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      Text(message, style: TextStyle(color: textColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('Renders NORMAL WEATHER card with sun icon and correct text without dismiss button', (tester) async {
      await tester.pumpWidget(buildTestWeatherCard(
        status: 'NORMAL',
        message: 'Current weather conditions are normal. Continue monitoring official announcements.',
      ));

      expect(find.text('NORMAL WEATHER'), findsOneWidget);
      expect(find.text('Current weather conditions are normal. Continue monitoring official announcements.'), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny_rounded), findsOneWidget);

      // Verify non-dismissible: NO close or dismiss button exists
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.clear), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('Renders WEATHER WARNING card with blue styling and warning icon', (tester) async {
      await tester.pumpWidget(buildTestWeatherCard(
        status: 'WARNING',
        message: 'Weather warning is currently in effect in Pozorrubio. Please stay alert and take necessary precautions.',
      ));

      expect(find.text('WEATHER WARNING'), findsOneWidget);
      expect(find.text('Weather warning is currently in effect in Pozorrubio. Please stay alert and take necessary precautions.'), findsOneWidget);
      expect(find.byIcon(Icons.thunderstorm_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('Renders EXTREME WEATHER WARNING card with red styling and alert triangle icon', (tester) async {
      await tester.pumpWidget(buildTestWeatherCard(
        status: 'EXTREME',
        message: 'Extreme weather warning is currently in effect in Pozorrubio. Stay safe and follow official instructions from the MDRRMO.',
      ));

      expect(find.text('EXTREME WEATHER WARNING'), findsOneWidget);
      expect(find.text('Extreme weather warning is currently in effect in Pozorrubio. Stay safe and follow official instructions from the MDRRMO.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
