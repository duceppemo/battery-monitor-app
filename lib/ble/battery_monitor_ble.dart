import 'package:battery_monitor_app/ble/ble_ids.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// The sole BLE boundary for the UI. Widgets receive device state and decoded
/// packets; they do not handle UUIDs, raw bytes or platform BLE APIs directly.
class BatteryMonitorBle {
  BatteryMonitorBle({FlutterReactiveBle? client})
      : _client = client ?? FlutterReactiveBle();

  final FlutterReactiveBle _client;

  Stream<DiscoveredDevice> scan() {
    return _client.scanForDevices(
      withServices: [BleIds.service],
      scanMode: ScanMode.lowLatency,
    );
  }

  Stream<ConnectionStateUpdate> connect(String deviceId) {
    return _client.connectToAdvertisingDevice(
      id: deviceId,
      withServices: [BleIds.service],
      connectionTimeout: const Duration(seconds: 10),
    );
  }

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
}
