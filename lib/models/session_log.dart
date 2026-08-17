import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';

class TestSessionMetadata {
  const TestSessionMetadata({
    this.name = '',
    this.chemistry = '',
    this.ratedCapacityAh,
    this.notes = '',
  });

  final String name;
  final String chemistry;
  final double? ratedCapacityAh;
  final String notes;

  String get displayName => name.trim().isEmpty ? 'Untitled test' : name.trim();
}

class TestSessionSummary {
  const TestSessionSummary({
    required this.metadata,
    required this.startedAt,
    required this.endedAt,
    required this.sampleCount,
    required this.eventCount,
    required this.voltageStartVolts,
    required this.voltageEndVolts,
    required this.voltageMinVolts,
    required this.voltageMaxVolts,
    required this.currentMinAmps,
    required this.currentMaxAmps,
    required this.powerMinWatts,
    required this.powerMaxWatts,
    required this.temperatureMinCelsius,
    required this.temperatureMaxCelsius,
    required this.netAmpHours,
    required this.netWattHours,
  });

  final TestSessionMetadata metadata;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int sampleCount;
  final int eventCount;
  final double? voltageStartVolts;
  final double? voltageEndVolts;
  final double? voltageMinVolts;
  final double? voltageMaxVolts;
  final double? currentMinAmps;
  final double? currentMaxAmps;
  final double? powerMinWatts;
  final double? powerMaxWatts;
  final double? temperatureMinCelsius;
  final double? temperatureMaxCelsius;
  final double? netAmpHours;
  final double? netWattHours;

  Duration get duration => startedAt == null || endedAt == null
      ? Duration.zero
      : endedAt!.difference(startedAt!);

  /// App-local capacity progress based on the net Ah change captured during
  /// this test, clamped to [0, 1] so a discharge that exceeds the rated
  /// capacity still reads as 100% used / 0% remaining instead of the two
  /// figures disagreeing. Available only for a positive discharge session
  /// with a positive, user-supplied rated capacity.
  double? get dischargedCapacityFraction {
    final capacity = metadata.ratedCapacityAh;
    final discharged = netAmpHours;
    if (capacity == null ||
        capacity <= 0 ||
        discharged == null ||
        discharged < 0) {
      return null;
    }
    return (discharged / capacity).clamp(0, 1).toDouble();
  }

  double? get estimatedRemainingCapacityAh {
    final capacity = metadata.ratedCapacityAh;
    final fraction = dischargedCapacityFraction;
    if (capacity == null || fraction == null) return null;
    return capacity * (1 - fraction);
  }

  double? get estimatedRemainingCapacityPercent {
    final fraction = dischargedCapacityFraction;
    return fraction == null ? null : 100 * (1 - fraction);
  }
}

class SessionEvent {
  const SessionEvent({
    required this.recordedAt,
    required this.type,
    this.detail = '',
  });

  final DateTime recordedAt;
  final String type;
  final String detail;
}

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

/// Bounded, app-local capture of decoded telemetry. Raw values remain intact
/// in history and exports even when the dashboard uses display filtering.
class SessionLog {
  SessionLog({this.maximumEntries = 7200, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int maximumEntries;
  final DateTime Function() _clock;
  final List<SessionLogEntry> _entries = [];
  final List<SessionEvent> _events = [];
  DateTime? _startedAt;
  DateTime? _endedAt;
  int? _lastSequence;
  TestSessionMetadata _metadata = const TestSessionMetadata();
  bool _isRecording = true;

  List<SessionLogEntry> get entries => List.unmodifiable(_entries);
  List<SessionEvent> get events => List.unmodifiable(_events);
  TestSessionMetadata get metadata => _metadata;
  DateTime? get startedAt => _startedAt;
  DateTime? get endedAt => _endedAt;
  bool get isRecording => _isRecording;

  TestSessionSummary get summary => _summarize(_endedAt ?? _clock());

  void start(TestSessionMetadata metadata) {
    _entries.clear();
    _events.clear();
    _metadata = metadata;
    _startedAt = _clock();
    _endedAt = null;
    _lastSequence = null;
    _isRecording = true;
    _addEvent('Session started', recordedAt: _startedAt!);
  }

  TestSessionSummary finish() {
    if (!_isRecording) return _summarize(_endedAt ?? _clock());
    _endedAt ??= _clock();
    _addEvent('Session finished', recordedAt: _endedAt!);
    _isRecording = false;
    return _summarize(_endedAt!);
  }

  /// Records a sparse app-side lifecycle or alarm transition alongside raw
  /// telemetry. Events stop when a user finishes the test session.
  void recordEvent(String type, {String detail = ''}) {
    if (!_isRecording) return;
    final now = _clock();
    _startedAt ??= now;
    _addEvent(type, detail: detail, recordedAt: now);
  }

  void add(BinaryTelemetryV1 telemetry) {
    if (!_isRecording || _lastSequence == telemetry.sequence) return;
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
    _events.clear();
    _startedAt = _isRecording ? _clock() : null;
    _endedAt = null;
    _lastSequence = null;
  }

  String toCsv({String? deviceInfo}) {
    final buffer = StringBuffer();
    if (deviceInfo != null && deviceInfo.isNotEmpty) {
      buffer.writeln('# device,${_csvField(deviceInfo)}');
    }
    buffer.writeln('# session_name,${_csvField(_metadata.displayName)}');
    if (_metadata.chemistry.trim().isNotEmpty) {
      buffer.writeln('# battery_chemistry,${_csvField(_metadata.chemistry)}');
    }
    if (_metadata.ratedCapacityAh != null) {
      buffer
          .writeln('# rated_capacity_ah,${_number(_metadata.ratedCapacityAh)}');
    }
    if (_metadata.notes.trim().isNotEmpty) {
      buffer.writeln('# notes,${_csvField(_metadata.notes)}');
    }
    if (_startedAt != null) {
      buffer
          .writeln('# started_at_utc,${_startedAt!.toUtc().toIso8601String()}');
    }
    if (_endedAt != null) {
      buffer.writeln('# ended_at_utc,${_endedAt!.toUtc().toIso8601String()}');
    }
    final summary = this.summary;
    buffer.writeln('# sample_count,${summary.sampleCount}');
    buffer.writeln('# event_count,${summary.eventCount}');
    buffer.writeln('# net_ah,${_number(summary.netAmpHours)}');
    buffer.writeln('# net_wh,${_number(summary.netWattHours)}');
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
    if (_events.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('# events');
      buffer.writeln('event_at_utc,event_type,detail');
      for (final event in _events) {
        buffer.writeln([
          event.recordedAt.toUtc().toIso8601String(),
          _csvField(event.type),
          _csvField(event.detail),
        ].join(','));
      }
    }
    return buffer.toString();
  }

  TestSessionSummary _summarize(DateTime end) {
    final first = _entries.isEmpty ? null : _entries.first;
    final last = _entries.isEmpty ? null : _entries.last;
    return TestSessionSummary(
      metadata: _metadata,
      startedAt: _startedAt,
      endedAt: _entries.isEmpty ? _endedAt : end,
      sampleCount: _entries.length,
      eventCount: _events.length,
      voltageStartVolts: first?.voltageVolts,
      voltageEndVolts: last?.voltageVolts,
      voltageMinVolts: _minimum(_entries.map((entry) => entry.voltageVolts)),
      voltageMaxVolts: _maximum(_entries.map((entry) => entry.voltageVolts)),
      currentMinAmps: _minimum(_entries.map((entry) => entry.currentAmps)),
      currentMaxAmps: _maximum(_entries.map((entry) => entry.currentAmps)),
      powerMinWatts: _minimum(_entries.map((entry) => entry.powerWatts)),
      powerMaxWatts: _maximum(_entries.map((entry) => entry.powerWatts)),
      temperatureMinCelsius:
          _minimum(_entries.map((entry) => entry.temperatureCelsius)),
      temperatureMaxCelsius:
          _maximum(_entries.map((entry) => entry.temperatureCelsius)),
      netAmpHours: first == null || last == null
          ? null
          : last.netAmpHours - first.netAmpHours,
      netWattHours: first == null || last == null
          ? null
          : last.netWattHours - first.netWattHours,
    );
  }

  static double? _minimum(Iterable<double?> values) {
    double? result;
    for (final value in values) {
      if (value != null &&
          value.isFinite &&
          (result == null || value < result)) {
        result = value;
      }
    }
    return result;
  }

  void _addEvent(
    String type, {
    String detail = '',
    required DateTime recordedAt,
  }) {
    _events.add(SessionEvent(
      recordedAt: recordedAt,
      type: type,
      detail: detail,
    ));
    if (_events.length > 500) _events.removeAt(0);
  }

  static double? _maximum(Iterable<double?> values) {
    double? result;
    for (final value in values) {
      if (value != null &&
          value.isFinite &&
          (result == null || value > result)) {
        result = value;
      }
    }
    return result;
  }

  static String _number(double? value) =>
      value == null ? '' : value.toStringAsFixed(6);

  static String _csvField(String value) {
    final normalized = value.replaceAll('\n', ' ');
    if (!normalized.contains(',') && !normalized.contains('"')) {
      return normalized;
    }
    return '"${normalized.replaceAll('"', '""')}"';
  }
}
