import 'dart:convert';

import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/dashboard_packet_v1.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmSettings {
  const AlarmSettings({
    this.lowVoltageEnabled = false,
    this.lowVoltage = 3.0,
    this.highVoltageEnabled = false,
    this.highVoltage = 4.25,
    this.currentEnabled = false,
    this.maxAbsoluteCurrent = 5.0,
    this.temperatureEnabled = false,
    this.maxTemperature = 60.0,
    this.sensorHealthEnabled = true,
  });

  final bool lowVoltageEnabled;
  final double lowVoltage;
  final bool highVoltageEnabled;
  final double highVoltage;
  final bool currentEnabled;
  final double maxAbsoluteCurrent;
  final bool temperatureEnabled;
  final double maxTemperature;
  final bool sensorHealthEnabled;

  AlarmSettings copyWith({
    bool? lowVoltageEnabled,
    double? lowVoltage,
    bool? highVoltageEnabled,
    double? highVoltage,
    bool? currentEnabled,
    double? maxAbsoluteCurrent,
    bool? temperatureEnabled,
    double? maxTemperature,
    bool? sensorHealthEnabled,
  }) =>
      AlarmSettings(
        lowVoltageEnabled: lowVoltageEnabled ?? this.lowVoltageEnabled,
        lowVoltage: lowVoltage ?? this.lowVoltage,
        highVoltageEnabled: highVoltageEnabled ?? this.highVoltageEnabled,
        highVoltage: highVoltage ?? this.highVoltage,
        currentEnabled: currentEnabled ?? this.currentEnabled,
        maxAbsoluteCurrent: maxAbsoluteCurrent ?? this.maxAbsoluteCurrent,
        temperatureEnabled: temperatureEnabled ?? this.temperatureEnabled,
        maxTemperature: maxTemperature ?? this.maxTemperature,
        sensorHealthEnabled: sensorHealthEnabled ?? this.sensorHealthEnabled,
      );

  List<String> evaluate(
      BinaryTelemetryV1 telemetry, DashboardSnapshot dashboard) {
    final alerts = <String>[];
    final voltage = telemetry.validVoltageVolts;
    final current = telemetry.validCurrentAmps;
    final temperature = telemetry.validTemperatureCelsius;
    if (lowVoltageEnabled && voltage != null && voltage < lowVoltage) {
      alerts.add('Low voltage: ${voltage.toStringAsFixed(3)} V');
    }
    if (highVoltageEnabled && voltage != null && voltage > highVoltage) {
      alerts.add('High voltage: ${voltage.toStringAsFixed(3)} V');
    }
    if (currentEnabled &&
        current != null &&
        current.abs() > maxAbsoluteCurrent) {
      alerts.add('Current limit: ${current.toStringAsFixed(3)} A');
    }
    if (temperatureEnabled &&
        temperature != null &&
        temperature > maxTemperature) {
      alerts.add('High temperature: ${temperature.toStringAsFixed(1)} C');
    }
    if (sensorHealthEnabled && dashboard.hasState && !dashboard.sensorOk) {
      alerts.add('INA228 sensor health error');
    }
    return alerts;
  }

  Map<String, Object> toJson() => {
        'lowVoltageEnabled': lowVoltageEnabled,
        'lowVoltage': lowVoltage,
        'highVoltageEnabled': highVoltageEnabled,
        'highVoltage': highVoltage,
        'currentEnabled': currentEnabled,
        'maxAbsoluteCurrent': maxAbsoluteCurrent,
        'temperatureEnabled': temperatureEnabled,
        'maxTemperature': maxTemperature,
        'sensorHealthEnabled': sensorHealthEnabled,
      };

  factory AlarmSettings.fromJson(Map<String, dynamic> json) => AlarmSettings(
        lowVoltageEnabled: json['lowVoltageEnabled'] == true,
        lowVoltage: (json['lowVoltage'] as num?)?.toDouble() ?? 3.0,
        highVoltageEnabled: json['highVoltageEnabled'] == true,
        highVoltage: (json['highVoltage'] as num?)?.toDouble() ?? 4.25,
        currentEnabled: json['currentEnabled'] == true,
        maxAbsoluteCurrent:
            (json['maxAbsoluteCurrent'] as num?)?.toDouble() ?? 5.0,
        temperatureEnabled: json['temperatureEnabled'] == true,
        maxTemperature: (json['maxTemperature'] as num?)?.toDouble() ?? 60.0,
        sensorHealthEnabled: json['sensorHealthEnabled'] != false,
      );
}

class AlarmSettingsStore {
  static const _key = 'alarm_settings_v1';

  Future<AlarmSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final text = preferences.getString(_key);
    if (text == null) return const AlarmSettings();
    try {
      return AlarmSettings.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      return const AlarmSettings();
    }
  }

  Future<void> save(AlarmSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(settings.toJson()));
  }
}
