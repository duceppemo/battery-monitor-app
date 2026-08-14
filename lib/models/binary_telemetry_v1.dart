import 'dart:typed_data';

/// Decoder for the firmware's fixed 20-byte Binary Telemetry v1 packet.
/// See docs/BLE_PROTOCOL.md for the cross-repository compatibility contract.
class BinaryTelemetryV1 {
  const BinaryTelemetryV1._({
    required this.flags,
    required this.sequence,
    required this.voltageVolts,
    required this.currentAmps,
    required this.powerWatts,
    required this.temperatureCelsius,
    required this.netAmpHours,
    required this.netWattHours,
  });

  static const packetLength = 20;
  static const version = 1;
  static const voltageValidFlag = 1 << 0;
  static const currentValidFlag = 1 << 1;
  static const powerValidFlag = 1 << 2;
  static const temperatureValidFlag = 1 << 3;

  final int flags;
  final int sequence;
  final double voltageVolts;
  final double currentAmps;
  final double powerWatts;
  final double temperatureCelsius;
  final double netAmpHours;
  final double netWattHours;

  bool get voltageValid => flags & voltageValidFlag != 0;
  bool get currentValid => flags & currentValidFlag != 0;
  bool get powerValid => flags & powerValidFlag != 0;
  bool get temperatureValid => flags & temperatureValidFlag != 0;

  double? get validVoltageVolts => voltageValid ? voltageVolts : null;
  double? get validCurrentAmps => currentValid ? currentAmps : null;
  double? get validPowerWatts => powerValid ? powerWatts : null;
  double? get validTemperatureCelsius =>
      temperatureValid ? temperatureCelsius : null;

  factory BinaryTelemetryV1.decode(List<int> bytes) {
    if (bytes.length != packetLength) {
      throw FormatException(
        'Binary Telemetry v1 must be $packetLength bytes, got ${bytes.length}.',
      );
    }

    final packet = Uint8List.fromList(bytes);
    final header = packet[0];
    final packetVersion = header >> 4;
    if (packetVersion != version) {
      throw FormatException(
          'Unsupported binary telemetry version $packetVersion.');
    }

    final data = ByteData.sublistView(packet);
    return BinaryTelemetryV1._(
      flags: header & 0x0f,
      sequence: data.getUint16(1, Endian.little),
      voltageVolts: data.getUint16(3, Endian.little) / 1000.0,
      currentAmps: _int24LE(packet, 5) / 1000.0,
      powerWatts: _int24LE(packet, 8) / 1000.0,
      temperatureCelsius: data.getInt8(11).toDouble(),
      netAmpHours: data.getInt32(12, Endian.little) / 1000.0,
      netWattHours: data.getInt32(16, Endian.little) / 1000.0,
    );
  }

  /// Local-only data source for exercising the dashboard without a monitor.
  factory BinaryTelemetryV1.simulated({
    required int sequence,
    required double voltageVolts,
    required double currentAmps,
    required double powerWatts,
    required double temperatureCelsius,
    required double netAmpHours,
    required double netWattHours,
  }) =>
      BinaryTelemetryV1._(
        flags: voltageValidFlag |
            currentValidFlag |
            powerValidFlag |
            temperatureValidFlag,
        sequence: sequence,
        voltageVolts: voltageVolts,
        currentAmps: currentAmps,
        powerWatts: powerWatts,
        temperatureCelsius: temperatureCelsius,
        netAmpHours: netAmpHours,
        netWattHours: netWattHours,
      );

  static int _int24LE(Uint8List packet, int offset) {
    var value =
        packet[offset] | (packet[offset + 1] << 8) | (packet[offset + 2] << 16);
    if ((value & 0x800000) != 0) {
      value |= ~0xffffff;
    }
    return value;
  }
}
