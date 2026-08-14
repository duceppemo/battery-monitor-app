import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';

class SessionLogEntry {
  const SessionLogEntry({
    required this.recordedAt,
    required this.elapsed,
    required this.sequence,
    required this.voltageVolts,
    required this.currentAmps,
    required this.powerWatts,
    required this.temperatureCelsius,
    required this.netAmpHours,
    required this.netWattHours,
  });

  final DateTime recordedAt;
  final Duration elapsed;
  final int sequence;
  final double? voltageVolts;
  final double? currentAmps;
  final double? powerWatts;
  final double? temperatureCelsius;
  final double netAmpHours;
  final double netWattHours;
}

/// Bounded, app-local capture of received live telemetry.  It deliberately
/// records decoded values rather than raw BLE packets so CSV files stay stable
/// even when a future transport protocol changes.
class SessionLog {
  SessionLog({this.maximumEntries = 7200, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int maximumEntries;
  final DateTime Function() _clock;
  final List<SessionLogEntry> _entries = [];
  DateTime? _startedAt;
  int? _lastSequence;

  List<SessionLogEntry> get entries => List.unmodifiable(_entries);

  void add(BinaryTelemetryV1 telemetry) {
    if (_lastSequence == telemetry.sequence) return;
    final now = _clock();
    _startedAt ??= now;
    _lastSequence = telemetry.sequence;
    _entries.add(SessionLogEntry(
      recordedAt: now,
      elapsed: now.difference(_startedAt!),
      sequence: telemetry.sequence,
      voltageVolts: telemetry.validVoltageVolts,
      currentAmps: telemetry.validCurrentAmps,
      powerWatts: telemetry.validPowerWatts,
      temperatureCelsius: telemetry.validTemperatureCelsius,
      netAmpHours: telemetry.netAmpHours,
      netWattHours: telemetry.netWattHours,
    ));
    if (_entries.length > maximumEntries) _entries.removeAt(0);
  }

  void clear() {
    _entries.clear();
    _startedAt = null;
    _lastSequence = null;
  }

  String toCsv({String? deviceInfo}) {
    final buffer = StringBuffer();
    if (deviceInfo != null && deviceInfo.isNotEmpty) {
      buffer.writeln('# device,$deviceInfo');
    }
    buffer.writeln(
      'recorded_at_utc,elapsed_s,sequence,voltage_v,current_a,power_w,temperature_c,net_ah,net_wh',
    );
    for (final entry in _entries) {
      buffer.writeln([
        entry.recordedAt.toUtc().toIso8601String(),
        (entry.elapsed.inMilliseconds / 1000).toStringAsFixed(3),
        entry.sequence,
        _number(entry.voltageVolts),
        _number(entry.currentAmps),
        _number(entry.powerWatts),
        _number(entry.temperatureCelsius),
        _number(entry.netAmpHours),
        _number(entry.netWattHours),
      ].join(','));
    }
    return buffer.toString();
  }

  static String _number(double? value) =>
      value == null ? '' : value.toStringAsFixed(6);
}
