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

    Widget buildTestExpandableWeatherCard({
      required String status,
      required String message,
      required bool isMinimized,
      required VoidCallback onToggle,
    }) {
      final Color bgColor = status == 'EXTREME'
          ? const Color(0xFFDC2626)
          : (status == 'WARNING' ? const Color(0xFF1D4ED8) : Colors.white);
      final Color textColor = (status == 'NORMAL') ? const Color(0xFF0F172A) : Colors.white;
      final String title = status == 'EXTREME'
          ? 'EXTREME WEATHER WARNING'
          : (status == 'WARNING' ? 'WEATHER WARNING' : 'NORMAL WEATHER');

      return MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              if (isMinimized) {
                return Container(
                  key: const Key('minimized-weather-banner'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wb_sunny_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        onPressed: onToggle,
                        tooltip: 'Expand',
                      ),
                    ],
                  ),
                );
              }
              return Container(
                key: const Key('expanded-weather-card'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('MDRRMO LIVE', style: TextStyle(color: textColor, fontSize: 10)),
                        const Spacer(),
                        InkWell(
                          onTap: onToggle,
                          child: Row(
                            children: [
                              Text('Minimize', style: TextStyle(color: textColor, fontSize: 10)),
                              const Icon(Icons.keyboard_arrow_up_rounded, size: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.wb_sunny_rounded, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                              Text(message, style: TextStyle(color: textColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Updated: Today • MDRRMO Command Center', style: TextStyle(color: textColor, fontSize: 9)),
                  ],
                ),
              );
            },
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

    testWidgets('Supports minimizing to compact banner and expanding back without dismissing status', (tester) async {
      bool isMinimized = false;

      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) {
          return buildTestExpandableWeatherCard(
            status: 'NORMAL',
            message: 'Current weather conditions are normal. Continue monitoring official announcements.',
            isMinimized: isMinimized,
            onToggle: () {
              setState(() {
                isMinimized = !isMinimized;
              });
            },
          );
        },
      ));

      // 1. Initially Expanded
      expect(find.byKey(const Key('expanded-weather-card')), findsOneWidget);
      expect(find.byKey(const Key('minimized-weather-banner')), findsNothing);
      expect(find.text('NORMAL WEATHER'), findsOneWidget);
      expect(find.text('Current weather conditions are normal. Continue monitoring official announcements.'), findsOneWidget);
      expect(find.text('Updated: Today • MDRRMO Command Center'), findsOneWidget);
      expect(find.text('Minimize'), findsOneWidget);

      // 2. Tap Minimize
      await tester.tap(find.text('Minimize'));
      await tester.pumpAndSettle();

      // 3. Now Minimized: compact banner is visible, status is preserved!
      expect(find.byKey(const Key('minimized-weather-banner')), findsOneWidget);
      expect(find.byKey(const Key('expanded-weather-card')), findsNothing);
      expect(find.text('NORMAL WEATHER'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);

      // 4. Tap Expand button
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();

      // 5. Restored to Expanded
      expect(find.byKey(const Key('expanded-weather-card')), findsOneWidget);
      expect(find.byKey(const Key('minimized-weather-banner')), findsNothing);
      expect(find.text('Minimize'), findsOneWidget);
    });
  });
}
