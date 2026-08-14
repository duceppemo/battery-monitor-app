import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/session_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records each sequence once and exports CSV', () {
    var tick = DateTime.utc(2026, 8, 13, 12);
    final log = SessionLog(clock: () => tick);
    final telemetry = BinaryTelemetryV1.decode(<int>[
      0x1f,
      0x01,
      0x00,
      0xd8,
      0x0c,
      0x64,
      0x00,
      0x00,
      0xc8,
      0x00,
      0x00,
      0x19,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);

    log.add(telemetry);
    tick = tick.add(const Duration(seconds: 1));
    log.add(telemetry);

    expect(log.entries, hasLength(1));
    expect(log.toCsv(deviceInfo: 'FW=0.3.0'), contains('# device,FW=0.3.0'));
    expect(log.toCsv(), contains('3.288000'));
  });
}
