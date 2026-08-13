import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a valid signed Binary Telemetry v1 packet', () {
    final packet = <int>[
      0x1f, // Version 1, all live values valid.
      0x34, 0x12, // Sequence 0x1234.
      0xd8, 0x0c, // 3.288 V.
      0xeb, 0xff, 0xff, // -21 mA.
      0xbc, 0x01, 0x00, // 444 mW.
      0x1d, // 29 C.
      0xd2, 0x04, 0x00, 0x00, // 1.234 Ah.
      0x2e, 0x16, 0x00, 0x00, // 5.678 Wh.
    ];

    final telemetry = BinaryTelemetryV1.decode(packet);

    expect(telemetry.sequence, 0x1234);
    expect(telemetry.validVoltageVolts, 3.288);
    expect(telemetry.validCurrentAmps, -0.021);
    expect(telemetry.validPowerWatts, 0.444);
    expect(telemetry.validTemperatureCelsius, 29.0);
    expect(telemetry.netAmpHours, 1.234);
    expect(telemetry.netWattHours, 5.678);
  });

  test('rejects an unsupported packet version', () {
    final packet = List<int>.filled(BinaryTelemetryV1.packetLength, 0);
    packet[0] = 0x20;

    expect(() => BinaryTelemetryV1.decode(packet), throwsFormatException);
  });
}
