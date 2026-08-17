import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:battery_monitor_app/ble/ble_ids.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/dashboard_packet_v1.dart';
import 'package:battery_monitor_app/models/control_status.dart';
import 'package:battery_monitor_app/models/firmware_update_status.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// The BLE contract consumed by screens. Keeping it separate from the native
/// implementation makes the UI testable without a phone Bluetooth stack.
abstract interface class BatteryMonitorBleClient {
  Stream<DiscoveredDevice> scan();

  Stream<ConnectionStateUpdate> connect(String deviceId);

  Stream<BinaryTelemetryV1> telemetry(String deviceId);

  Stream<DashboardPacketV1> dashboard(String deviceId);

  Stream<FirmwareUpdateStatus> firmwareUpdateStatus(String deviceId);

  Stream<ControlStatus> controlStatus(String deviceId);

  Future<void> sendControl(String deviceId, List<int> command);

  Future<void> saveWifi(String deviceId, String ssid, String password);

  Future<void> clearWifi(String deviceId);

  Future<String> deviceInfo(String deviceId);

  Future<void> installFirmware(
    String deviceId,
    Uint8List firmware, {
    required void Function(double progress) onProgress,
  });
}

/// The sole native BLE boundary for the UI. Widgets receive device state and
/// decoded packets; they do not handle UUIDs, raw bytes or platform APIs.
class BatteryMonitorBle implements BatteryMonitorBleClient {
  BatteryMonitorBle({FlutterReactiveBle? client})
      : _client = client ?? FlutterReactiveBle();

  final FlutterReactiveBle _client;
  int _nextControlRequestId = 0;

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
  Stream<FirmwareUpdateStatus> firmwareUpdateStatus(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.firmwareUpdateStatus,
      deviceId: deviceId,
    );
    return _client
        .subscribeToCharacteristic(characteristic)
        .map(FirmwareUpdateStatus.decode);
  }

  @override
  Stream<ControlStatus> controlStatus(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.controlStatus,
      deviceId: deviceId,
    );
    return _client.subscribeToCharacteristic(characteristic).map(ControlStatus.decode);
  }

  @override
  Future<void> sendControl(String deviceId, List<int> command) async {
    if (command.isEmpty) throw ArgumentError.value(command, 'command');
    final characteristic = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.control,
      deviceId: deviceId,
    );
    var requestId = (++_nextControlRequestId) & 0xffff;
    if (requestId == 0) requestId = (++_nextControlRequestId) & 0xffff;
    final response = Completer<ControlStatus>();
    final subscription = controlStatus(deviceId).listen(
      (status) {
        if (status.command == command.first && status.requestId == requestId &&
            !response.isCompleted) {
          response.complete(status);
        }
      },
      onError: (Object error) {
        if (!response.isCompleted) response.completeError(error);
      },
    );
    final framed = Uint8List(command.length + 2)
      ..setRange(0, command.length, command);
    ByteData.sublistView(framed).setUint16(command.length, requestId, Endian.little);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _client.writeCharacteristicWithResponse(characteristic, value: framed);
      final status = await response.future.timeout(const Duration(seconds: 4));
      if (status.result != ControlResult.applied) {
        throw StateError('Monitor command ${status.description}.');
      }
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> saveWifi(String deviceId, String ssid, String password) async {
    final ssidBytes = utf8.encode(ssid);
    final passwordBytes = utf8.encode(password);
    if (ssidBytes.isEmpty || ssidBytes.length > 32) {
      throw ArgumentError.value(ssid, 'ssid', 'Must be 1-32 UTF-8 bytes.');
    }
    if (passwordBytes.length > 64) {
      throw ArgumentError.value(
          password, 'password', 'Must be at most 64 UTF-8 bytes.');
    }
    // The payload can reach 99 bytes, well past the default 20-byte usable
    // ATT payload. A short SSID/password may fit anyway; let the write
    // itself surface a clear failure if negotiation didn't help enough.
    try {
      await _client.requestMtu(deviceId: deviceId, mtu: 247);
    } on Object {
      // Ignored: see above.
    }
    await sendControl(deviceId, [
      7,
      ssidBytes.length,
      ...ssidBytes,
      passwordBytes.length,
      ...passwordBytes,
    ]);
  }

  @override
  Future<void> clearWifi(String deviceId) => sendControl(deviceId, const [8]);

  @override
  Future<String> deviceInfo(String deviceId) async {
    final characteristic = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.deviceInfo,
      deviceId: deviceId,
    );
    final value = await _client.readCharacteristic(characteristic);
    return String.fromCharCodes(value);
  }

  @override
  Future<void> installFirmware(
    String deviceId,
    Uint8List firmware, {
    required void Function(double progress) onProgress,
  }) async {
    if (firmware.isEmpty) throw ArgumentError.value(firmware, 'firmware');

    final transfer = QualifiedCharacteristic(
      serviceId: BleIds.service,
      characteristicId: BleIds.firmwareTransfer,
      deviceId: deviceId,
    );
    final receiving = Completer<void>();
    final verified = Completer<void>();
    final failure = Completer<Object>();
    final subscription = firmwareUpdateStatus(deviceId).listen(
      (status) {
        if (status.state == FirmwareUpdateState.receiving &&
            !receiving.isCompleted) {
          receiving.complete();
        } else if (status.state == FirmwareUpdateState.verified &&
            !verified.isCompleted) {
          verified.complete();
        } else if (status.state == FirmwareUpdateState.error &&
            !failure.isCompleted) {
          failure.complete(StateError(status.errorDescription));
        }
      },
      onError: (Object error) {
        if (!failure.isCompleted) failure.complete(error);
      },
    );

    try {
      // Give the CCCD subscription one connection interval to become active
      // before the start command emits its first status notification.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      int mtu = 23;
      try {
        mtu = await _client.requestMtu(deviceId: deviceId, mtu: 247);
      } on Object {
        // The negotiated/default MTU still works; it is simply slower.
      }
      // ATT allows MTU - 3 value bytes; each data frame uses five of those
      // bytes for its command/offset. The 15-byte lower bound is the
      // universally available 23-byte-MTU fallback.
      final chunkSize = (mtu - 8).clamp(15, 180);
      final start = ByteData(9)
        ..setUint8(0, 0xA0)
        ..setUint32(1, firmware.length, Endian.little)
        ..setUint32(5, _crc32(firmware), Endian.little);
      await _client.writeCharacteristicWithResponse(
        transfer,
        value: start.buffer.asUint8List(),
      );
      await Future.any<void>([
        receiving.future.timeout(const Duration(seconds: 5)),
        failure.future.then<void>((error) => throw error),
      ]);

      for (var offset = 0; offset < firmware.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, firmware.length);
        final packet = Uint8List(5 + end - offset);
        ByteData.sublistView(packet)
          ..setUint8(0, 0xA1)
          ..setUint32(1, offset, Endian.little);
        packet.setRange(5, packet.length, firmware, offset);
        await Future.any<void>([
          _client.writeCharacteristicWithResponse(transfer, value: packet),
          failure.future.then<void>((error) => throw error),
        ]);
        onProgress(end / firmware.length);
      }

      await _client.writeCharacteristicWithResponse(transfer, value: [0xA2]);
      await Future.any<void>([
        verified.future.timeout(const Duration(seconds: 10)),
        failure.future.then<void>((error) => throw error),
      ]);
    } on Object {
      try {
        await _client.writeCharacteristicWithResponse(transfer, value: [0xA3]);
      } on Object {
        // The link may already be gone after a successful reboot.
      }
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
      }
    }
    return (~crc) & 0xffffffff;
  }
}
