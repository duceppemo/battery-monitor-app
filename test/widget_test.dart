import 'dart:typed_data';

import 'package:battery_monitor_app/ble/battery_monitor_ble.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/dashboard_packet_v1.dart';
import 'package:battery_monitor_app/models/control_status.dart';
import 'package:battery_monitor_app/models/firmware_update_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battery_monitor_app/main.dart';

void main() {
  testWidgets('shows the Battery Monitor dashboard',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      BatteryMonitorApp(
        ble: _FakeBatteryMonitorBle(),
      ),
    );

    expect(find.text('Battery Monitor'), findsOneWidget);
    expect(find.text('Scan for monitors'), findsOneWidget);
    expect(find.text('Connection & app update'), findsOneWidget);
    expect(find.text('Monitor firmware update'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });
}

class _FakeBatteryMonitorBle implements BatteryMonitorBleClient {
  @override
  Stream<DiscoveredDevice> scan() => const Stream.empty();

  @override
  Stream<ConnectionStateUpdate> connect(String deviceId) =>
      const Stream.empty();

  @override
  Stream<BinaryTelemetryV1> telemetry(String deviceId) => const Stream.empty();

  @override
  Stream<DashboardPacketV1> dashboard(String deviceId) => const Stream.empty();

  @override
  Stream<FirmwareUpdateStatus> firmwareUpdateStatus(String deviceId) =>
      const Stream.empty();

  @override
  Stream<ControlStatus> controlStatus(String deviceId) => const Stream.empty();

  @override
  Future<void> sendControl(String deviceId, List<int> command) async {}

  @override
  Future<void> saveWifi(String deviceId, String ssid, String password) async {}

  @override
  Future<void> clearWifi(String deviceId) async {}

  @override
  Future<void> saveBatteryProfile(
    String deviceId,
    double capacityAh,
    double chargedVoltage,
  ) async {}

  @override
  Future<void> syncBatteryFull(String deviceId) async {}

  @override
  Future<void> resetBatteryHistory(String deviceId) async {}

  @override
  Future<String> deviceInfo(String deviceId) async => '';

  @override
  Future<void> installFirmware(String deviceId, Uint8List firmware,
      {required void Function(double progress) onProgress}) async {}
}
