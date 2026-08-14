import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/telemetry_presentation_filter.dart';
import 'package:flutter_test/flutter_test.dart';

BinaryTelemetryV1 _sample({
  required int sequence,
  required double voltage,
  required double current,
}) =>
    BinaryTelemetryV1.simulated(
      sequence: sequence,
      voltageVolts: voltage,
      currentAmps: current,
      powerWatts: voltage * current,
      temperatureCelsius: 25,
      netAmpHours: 0,
      netWattHours: 0,
    );

void main() {
  test('raw mode presents received values unchanged', () {
    final filter = TelemetryPresentationFilter();

    final shown = filter.update(_sample(sequence: 1, voltage: 3.2, current: 1));

    expect(shown.voltageVolts, 3.2);
    expect(shown.currentAmps, 1);
  });

  test('stable mode smooths the live presentation without changing raw input',
      () {
    final filter =
        TelemetryPresentationFilter(mode: TelemetryFilterMode.stable);
    filter.update(_sample(sequence: 1, voltage: 3, current: 0));

    final shown = filter.update(_sample(sequence: 2, voltage: 4, current: 1));

    expect(shown.voltageVolts, closeTo(3.22, 0.000001));
    expect(shown.currentAmps, closeTo(0.22, 0.000001));
  });

  test('changing mode resets the filter so the next sample is immediate', () {
    final filter =
        TelemetryPresentationFilter(mode: TelemetryFilterMode.stable);
    filter.update(_sample(sequence: 1, voltage: 3, current: 0));
    filter.select(TelemetryFilterMode.fast);

    final shown = filter.update(_sample(sequence: 2, voltage: 4, current: 1));

    expect(shown.voltageVolts, 4);
    expect(shown.currentAmps, 1);
  });
}
