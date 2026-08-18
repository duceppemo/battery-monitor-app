import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/session_log.dart';
import 'package:battery_monitor_app/screens/capacity_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TestSessionSummary _syntheticSummary({required double ratedCapacityAh}) {
  var tick = DateTime.utc(2026, 8, 18, 9);
  final log = SessionLog(clock: () => tick);
  log.start(TestSessionMetadata(
    name: 'Bench discharge',
    chemistry: 'LiFePO4',
    ratedCapacityAh: ratedCapacityAh,
    notes: 'Room temperature',
  ));
  for (var i = 0; i < 20; i++) {
    final fraction = i / 19;
    log.add(BinaryTelemetryV1.simulated(
      sequence: i + 1,
      voltageVolts: 3.6 - 0.4 * fraction,
      currentAmps: 2,
      powerWatts: 7,
      temperatureCelsius: 24,
      netAmpHours: 9 * fraction,
      netWattHours: 30 * fraction,
    ));
    tick = tick.add(const Duration(minutes: 3));
  }
  return log.finish();
}

void main() {
  testWidgets('renders a pass verdict, chart and metrics for a finished test',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = _syntheticSummary(ratedCapacityAh: 10);
    await tester.pumpWidget(MaterialApp(
      home: CapacityReportScreen(
        summary: summary,
        entries: const [],
        deviceInfo: 'FW=0.5.9',
      ),
    ));

    expect(find.text('Bench discharge report'), findsOneWidget);
    expect(find.text('PASS'), findsOneWidget);
    expect(find.text('Discharge curve'), findsOneWidget);
    expect(find.text('Capacity'), findsOneWidget);
    expect(find.text('Rate adjustment (optional)'), findsOneWidget);
    expect(find.text('Session details'), findsOneWidget);
    expect(find.text('LiFePO4'), findsOneWidget);
  });

  testWidgets('recomputes the verdict when Peukert inputs are entered',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = _syntheticSummary(ratedCapacityAh: 20);
    await tester.pumpWidget(MaterialApp(
      home: CapacityReportScreen(summary: summary, entries: const []),
    ));

    // 9 Ah out of 20 rated = 45%, below the default 80% threshold.
    expect(find.text('FAIL'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Peukert exponent'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reference rate (hours)'),
      '5',
    );
    await tester.pump();

    // Discharge current is well below the fast reference rate here, so the
    // rate-adjusted capacity comes out lower still -- still a fail, but the
    // rate-adjusted metric card should now be visible and not crash.
    expect(find.text('Rate-adjusted'), findsOneWidget);
  });

  testWidgets('shows inconclusive when no rated capacity was set',
      (tester) async {
    final summary = _syntheticSummary(ratedCapacityAh: 0);
    await tester.pumpWidget(MaterialApp(
      home: CapacityReportScreen(summary: summary, entries: const []),
    ));

    expect(find.text('INCONCLUSIVE'), findsOneWidget);
    expect(
      find.text('Set a rated capacity when starting a test to get a verdict.'),
      findsOneWidget,
    );
  });
}
