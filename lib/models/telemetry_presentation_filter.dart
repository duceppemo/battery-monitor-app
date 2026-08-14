import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';

/// Local display smoothing only. Raw BLE telemetry continues to drive the
/// session log, alarms, exports, and firmware-sourced energy counters.
enum TelemetryFilterMode {
  raw('Raw', 1.0),
  fast('Fast', 0.55),
  stable('Stable', 0.22);

  const TelemetryFilterMode(this.label, this.alpha);

  final String label;
  final double alpha;
}

class PresentedTelemetry {
  const PresentedTelemetry({
    required this.voltageVolts,
    required this.currentAmps,
    required this.powerWatts,
    required this.temperatureCelsius,
  });

  final double? voltageVolts;
  final double? currentAmps;
  final double? powerWatts;
  final double? temperatureCelsius;
}

/// Independent exponential moving averages for values shown on the live card.
/// An invalid raw value remains invalid; it is never replaced with a previous
/// filtered reading.
class TelemetryPresentationFilter {
  TelemetryPresentationFilter({this.mode = TelemetryFilterMode.raw});

  TelemetryFilterMode mode;
  double? _voltage;
  double? _current;
  double? _power;
  double? _temperature;

  void select(TelemetryFilterMode nextMode) {
    if (mode == nextMode) return;
    mode = nextMode;
    reset();
  }

  void reset() {
    _voltage = null;
    _current = null;
    _power = null;
    _temperature = null;
  }

  PresentedTelemetry update(BinaryTelemetryV1 telemetry) => PresentedTelemetry(
        voltageVolts: _next(telemetry.validVoltageVolts, (value) {
          _voltage = value;
        }, _voltage),
        currentAmps: _next(telemetry.validCurrentAmps, (value) {
          _current = value;
        }, _current),
        powerWatts: _next(telemetry.validPowerWatts, (value) {
          _power = value;
        }, _power),
        temperatureCelsius: _next(telemetry.validTemperatureCelsius, (value) {
          _temperature = value;
        }, _temperature),
      );

  double? _next(
    double? raw,
    void Function(double) save,
    double? previous,
  ) {
    if (raw == null || !raw.isFinite) return null;
    if (mode == TelemetryFilterMode.raw || previous == null) {
      save(raw);
      return raw;
    }
    final filtered = previous + mode.alpha * (raw - previous);
    save(filtered);
    return filtered;
  }
}
