import 'package:flutter_test/flutter_test.dart';

import 'package:battery_monitor_app/main.dart';

void main() {
  testWidgets('shows the Battery Monitor dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const BatteryMonitorApp());

    expect(find.text('Battery Monitor'), findsOneWidget);
    expect(find.text('Scan for monitors'), findsOneWidget);
  });
}
