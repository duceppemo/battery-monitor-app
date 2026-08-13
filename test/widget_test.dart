import 'package:battery_monitor_app/ble/battery_monitor_ble.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'package:battery_monitor_app/main.dart';

void main() {
  testWidgets('shows the Battery Monitor dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(BatteryMonitorApp(ble: _FakeBatteryMonitorBle()));

    expect(find.text('Battery Monitor'), findsOneWidget);
    expect(find.text('Scan for monitors'), findsOneWidget);
  });
}

class _FakeBatteryMonitorBle implements BatteryMonitorBleClient {
  @override
  Stream<DiscoveredDevice> scan() => const Stream.empty();

  @override
  Stream<ConnectionStateUpdate> connect(String deviceId) => const Stream.empty();

  @override
  Stream<BinaryTelemetryV1> telemetry(String deviceId) => const Stream.empty();
}
