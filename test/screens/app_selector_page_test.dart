import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/screens/app_selector_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.minizivpn.app/core');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getInstalledApps') {
        return [
          {'name': 'Chrome', 'package': 'com.android.chrome'},
          {'name': 'YouTube', 'package': 'com.google.android.youtube'},
          {'name': 'Maps', 'package': 'com.google.android.apps.maps'},
        ];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('AppSelectorPage loads and filters apps correctly', (WidgetTester tester) async {
    // Pump the widget
    await tester.pumpWidget(const MaterialApp(
      home: AppSelectorPage(initialSelected: []),
    ));

    // Wait for the async load
    await tester.pumpAndSettle();

    // Verify initial load
    expect(find.text('Chrome'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Maps'), findsOneWidget);

    // Enter filter text "chrome"
    await tester.enterText(find.byType(TextField), 'chrome');
    await tester.pump(); // Rebuild

    // Verify filter results
    expect(find.text('Chrome'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);
    expect(find.text('Maps'), findsNothing);

    // Clear filter
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    // Verify all back
    expect(find.text('Chrome'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);

    // Filter by package name "google"
    await tester.enterText(find.byType(TextField), 'google');
    await tester.pump();

    // Chrome package is com.android.chrome (no google)
    expect(find.text('Chrome'), findsNothing);
    // YouTube package is com.google.android.youtube
    expect(find.text('YouTube'), findsOneWidget);
    // Maps package is com.google.android.apps.maps
    expect(find.text('Maps'), findsOneWidget);
  });
}
