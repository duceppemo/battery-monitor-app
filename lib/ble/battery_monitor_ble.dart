import 'package:battery_monitor_app/ble/ble_ids.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/dashboard_packet_v1.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// The BLE contract consumed by screens. Keeping it separate from the native
/// implementation makes the UI testable without a phone Bluetooth stack.
abstract interface class BatteryMonitorBleClient {
  Stream<DiscoveredDevice> scan();

  Stream<ConnectionStateUpdate> connect(String deviceId);

  Stream<BinaryTelemetryV1> telemetry(String deviceId);

  Stream<DashboardPacketV1> dashboard(String deviceId);

  Future<void> sendControl(String deviceId, List<int> command);
}

/// The sole native BLE boundary for the UI. Widgets receive device state and
/// decoded packets; they do not handle UUIDs, raw bytes or platform APIs.
class BatteryMonitorBle implements BatteryMonitorBleClient {
  BatteryMonitorBle({FlutterReactiveBle? client})
      : _client = client ?? FlutterReactiveBle();

  final FlutterReactiveBle _client;

  @override
  Stream<DiscoveredDevice> scan() {
    return _client.scanForDevices(
      withServices: [BleIds.service],
      scanMode: ScanMode.lowLatency,
    );
  }

  @override
  Stream<ConnectionStateUpdate> connect(String deviceId) {
    return _client.connectToAdvertisingDevice(
      id: deviceId,
      withServices: [BleIds.service],
      prescanDuration: const Duration(seconds: 3),
      connectionTimeout: const Duration(seconds: 10),
    );
  }

  @override
  Stream<BinaryTelemetryV1> telemetry(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.binaryTelemetry,
      deviceId: deviceId,
    );
    return _client
        .subscribeToCharacteristic(characteristic)
        .map(BinaryTelemetryV1.decode);
  }

  @override
  Stream<DashboardPacketV1> dashboard(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.dashboard,
      deviceId: deviceId,
    );
    return _client
        .subscribeToCharacteristic(characteristic)
        .map(DashboardPacketV1.decode);
  }

  @override
  Future<void> sendControl(String deviceId, List<int> command) {
    final characteristic = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.control,
      deviceId: deviceId,
    );
    return _client.writeCharacteristicWithResponse(characteristic,
        value: command);
  }
}
