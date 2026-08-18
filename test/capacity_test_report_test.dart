import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/capacity_test_report.dart';
import 'package:battery_monitor_app/models/session_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs a controlled synthetic discharge through a real [SessionLog] so the
/// report math is exercised the same way it would be from live telemetry,
/// without needing a monitor or a real battery. [samples] is the number of
/// telemetry points spread evenly across [duration]; capacity and voltage
/// are linearly interpolated from start to end.
TestSessionSummary _syntheticDischarge({
  required double ratedCapacityAh,
  required double startVoltage,
  required double endVoltage,
  required double dischargedAh,
  required Duration duration,
  int samples = 2,
}) {
  var tick = DateTime.utc(2026, 8, 18, 9);
  final log = SessionLog(clock: () => tick);
  log.start(TestSessionMetadata(
    name: 'Synthetic discharge',
    chemistry: 'Test',
    ratedCapacityAh: ratedCapacityAh,
  ));

  final stepDuration = Duration(
    microseconds: duration.inMicroseconds ~/ (samples - 1),
  );
  for (var i = 0; i < samples; i++) {
    final fraction = i / (samples - 1);
    log.add(BinaryTelemetryV1.simulated(
      sequence: i + 1,
      voltageVolts: startVoltage + (endVoltage - startVoltage) * fraction,
      currentAmps: dischargedAh / (duration.inMilliseconds / 3600000.0),
      powerWatts: 0,
      temperatureCelsius: 25,
      netAmpHours: dischargedAh * fraction,
      netWattHours: 0,
    ));
    if (i < samples - 1) tick = tick.add(stepDuration);
  }
  return log.finish();
}

void main() {
  test('computes observed capacity, rate and raw percent of rated', () {
    // 10 Ah rated, 4 Ah delivered over 2 hours -> 2 A average -> 0.2C.
    final summary = _syntheticDischarge(
      ratedCapacityAh: 10,
      startVoltage: 4.1,
      endVoltage: 3.6,
      dischargedAh: 4,
      duration: const Duration(hours: 2),
    );

    final report = CapacityTestReport.compute(
      summary: summary,
      entries: const [],
    );

    expect(report.observedCapacityAh, closeTo(4, 1e-9));
    expect(report.averageDischargeCurrentAmps, closeTo(2, 1e-9));
    expect(report.averageDischargeRateC, closeTo(0.2, 1e-9));
    expect(report.percentOfRated, closeTo(40, 1e-9));
    expect(report.peukertAdjustedCapacityAh, isNull);
    expect(report.isRateAdjusted, isFalse);
    expect(report.verdictPercent, closeTo(40, 1e-9));
  });

  test('applies the Peukert adjustment only when both inputs are given', () {
    // Same 10 Ah / 4 Ah / 2 A / 2 h scenario as above. Reference rate is
    // C/20 (0.5 A). With exponent = 2, ratio^(exponent-1) = ratio^1 = 4,
    // which is exact to verify by hand: 4 Ah * 4 = 16 Ah.
    final summary = _syntheticDischarge(
      ratedCapacityAh: 10,
      startVoltage: 4.1,
      endVoltage: 3.6,
      dischargedAh: 4,
      duration: const Duration(hours: 2),
    );

    final adjusted = CapacityTestReport.compute(
      summary: summary,
      entries: const [],
      peukertExponent: 2.0,
      referenceDischargeHours: 20,
    );

    expect(adjusted.isRateAdjusted, isTrue);
    expect(adjusted.peukertAdjustedCapacityAh, closeTo(16, 1e-9));
    expect(adjusted.peukertAdjustedPercentOfRated, closeTo(160, 1e-9));
    expect(adjusted.verdictPercent, closeTo(160, 1e-9));

    // Withholding either input must leave the report unadjusted rather than
    // guessing a default -- an unreviewed constant could make a pass/fail
    // verdict silently wrong for the wrong chemistry.
    final missingExponent = CapacityTestReport.compute(
      summary: summary,
      entries: const [],
      referenceDischargeHours: 20,
    );
    expect(missingExponent.isRateAdjusted, isFalse);

    final missingReference = CapacityTestReport.compute(
      summary: summary,
      entries: const [],
      peukertExponent: 2.0,
    );
    expect(missingReference.isRateAdjusted, isFalse);
  });

  test('an exponent of 1 leaves capacity unadjusted regardless of rate', () {
    final summary = _syntheticDischarge(
      ratedCapacityAh: 10,
      startVoltage: 4.1,
      endVoltage: 3.6,
      dischargedAh: 4,
      duration: const Duration(hours: 2),
    );

    final report = CapacityTestReport.compute(
      summary: summary,
      entries: const [],
      peukertExponent: 1.0,
      referenceDischargeHours: 20,
    );

    // ratio^(1-1) = ratio^0 = 1, so the adjusted figure equals the raw one.
    expect(report.peukertAdjustedCapacityAh, closeTo(4, 1e-9));
    expect(report.peukertAdjustedPercentOfRated, closeTo(40, 1e-9));
  });

  test('verdict is pass, fail or inconclusive based on the threshold', () {
    final passSummary = _syntheticDischarge(
      ratedCapacityAh: 10,
      startVoltage: 4.1,
      endVoltage: 3.9,
      dischargedAh: 9,
      duration: const Duration(hours: 1),
    );
    expect(
      CapacityTestReport.compute(summary: passSummary, entries: const [])
          .verdict,
      CapacityTestVerdict.pass,
    );

    final failSummary = _syntheticDischarge(
      ratedCapacityAh: 10,
      startVoltage: 4.1,
      endVoltage: 3.2,
      dischargedAh: 5,
      duration: const Duration(hours: 1),
    );
    expect(
      CapacityTestReport.compute(summary: failSummary, entries: const [])
          .verdict,
      CapacityTestVerdict.fail,
    );

    final noRatedCapacity = _syntheticDischarge(
      ratedCapacityAh: 0,
      startVoltage: 4.1,
      endVoltage: 3.2,
      dischargedAh: 5,
      duration: const Duration(hours: 1),
    );
    expect(
      CapacityTestReport.compute(summary: noRatedCapacity, entries: const [])
          .verdict,
      CapacityTestVerdict.inconclusive,
    );
  });

  test('discharge curve is decimated but keeps its endpoints and order', () {
    var tick = DateTime.utc(2026, 8, 18, 9);
    final log = SessionLog(maximumEntries: 2000, clock: () => tick);
    log.start(const TestSessionMetadata(
      name: 'Long discharge',
      ratedCapacityAh: 10,
    ));
    const sampleCount = 1000;
    for (var i = 0; i < sampleCount; i++) {
      final fraction = i / (sampleCount - 1);
      log.add(BinaryTelemetryV1.simulated(
        sequence: i + 1,
        voltageVolts: 4.2 - 0.6 * fraction,
        currentAmps: 2,
        powerWatts: 0,
        temperatureCelsius: 25,
        netAmpHours: 4 * fraction,
        netWattHours: 0,
      ));
      tick = tick.add(const Duration(seconds: 5));
    }
    final summary = log.finish();

    final report = CapacityTestReport.compute(
      summary: summary,
      entries: log.entries,
      maxCurvePoints: 200,
    );

    expect(report.curve, isNotEmpty);
    expect(report.curve.length, lessThanOrEqualTo(200));
    expect(report.curve.first.dischargedAmpHours, closeTo(0, 1e-9));
    expect(report.curve.last.dischargedAmpHours, closeTo(4, 1e-9));
    expect(report.curve.first.voltageVolts, closeTo(4.2, 1e-9));
    expect(report.curve.last.voltageVolts, closeTo(3.6, 1e-9));
    for (var i = 1; i < report.curve.length; i++) {
      expect(
        report.curve[i].dischargedAmpHours,
        greaterThanOrEqualTo(report.curve[i - 1].dischargedAmpHours),
      );
    }
  });

  test('no entries with voltage produce an empty curve without crashing',
      () {
    final summary = _syntheticDischarge(
      ratedCapacityAh: 10,
      startVoltage: 4.1,
      endVoltage: 3.6,
      dischargedAh: 4,
      duration: const Duration(hours: 2),
    );

    final report = CapacityTestReport.compute(
      summary: summary,
      entries: const [],
    );

    expect(report.curve, isEmpty);
  });
}
