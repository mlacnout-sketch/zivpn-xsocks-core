import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/screens/tabs/logs_tab.dart';

void main() {
  testWidgets('LogsTab calls onClearLogs when delete button is tapped', (WidgetTester tester) async {
    // Arrange
    final logs = ['Log 1', 'Log 2', 'Log 3'];
    final scrollController = ScrollController();
    bool clearCallbackCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogsTab(
            logs: logs,
            scrollController: scrollController,
            onClearLogs: () {
              clearCallbackCalled = true;
            },
          ),
        ),
      ),
    );

    // Act
    final clearButtonFinder = find.byTooltip('Clear Logs'); // Use tooltip for better specificity
    expect(clearButtonFinder, findsOneWidget);

    await tester.tap(clearButtonFinder);
    await tester.pump();

    // Assert
    expect(clearCallbackCalled, isTrue);
  });
}
