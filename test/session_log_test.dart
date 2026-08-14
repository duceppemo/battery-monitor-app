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

  test('summarizes a named test and includes metadata in CSV', () {
    var tick = DateTime.utc(2026, 8, 13, 12);
    final log = SessionLog(clock: () => tick);
    log.start(const TestSessionMetadata(
      name: 'Capacity test',
      chemistry: 'Li-ion',
      ratedCapacityAh: 2.5,
      notes: 'Room temperature',
    ));
    log.add(BinaryTelemetryV1.simulated(
      sequence: 1,
      voltageVolts: 4.1,
      currentAmps: 1,
      powerWatts: 4.1,
      temperatureCelsius: 25,
      netAmpHours: 0.2,
      netWattHours: 0.8,
    ));
    log.recordEvent('Low voltage', detail: '3.000 V threshold');
    tick = tick.add(const Duration(minutes: 1));
    log.add(BinaryTelemetryV1.simulated(
      sequence: 2,
      voltageVolts: 4,
      currentAmps: 1.2,
      powerWatts: 4.8,
      temperatureCelsius: 26,
      netAmpHours: 0.3,
      netWattHours: 1.2,
    ));

    final summary = log.finish();

    expect(summary.metadata.displayName, 'Capacity test');
    expect(summary.sampleCount, 2);
    expect(summary.eventCount, 3);
    expect(summary.duration, const Duration(minutes: 1));
    expect(summary.netAmpHours, closeTo(0.1, 0.000001));
    expect(summary.voltageStartVolts, 4.1);
    expect(summary.voltageEndVolts, 4);
    expect(log.isRecording, isFalse);
    expect(log.toCsv(), contains('# session_name,Capacity test'));
    expect(log.toCsv(), contains('# rated_capacity_ah,2.500000'));
    expect(log.toCsv(), contains('# events'));
    expect(log.toCsv(), contains('Low voltage,3.000 V threshold'));
  });
}
