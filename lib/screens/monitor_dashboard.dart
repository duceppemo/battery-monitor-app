import 'dart:async';

import 'package:battery_monitor_app/ble/battery_monitor_ble.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class MonitorDashboard extends StatefulWidget {
  const MonitorDashboard({super.key});

  @override
  State<MonitorDashboard> createState() => _MonitorDashboardState();
}

class _MonitorDashboardState extends State<MonitorDashboard> {
  final BatteryMonitorBle _ble = BatteryMonitorBle();
  final Map<String, DiscoveredDevice> _devices = {};

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<BinaryTelemetryV1>? _telemetrySubscription;
  BinaryTelemetryV1? _telemetry;
  String _status = 'Ready to scan';
  String? _connectedDeviceId;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _telemetrySubscription?.cancel();
    super.dispose();
  }

  void _scan() {
    _scanSubscription?.cancel();
    setState(() {
      _devices.clear();
      _status = 'Scanning for Battery Monitor…';
    });
    _scanSubscription = _ble.scan().listen(
      (device) {
        if (!mounted) return;
        setState(() {
          _devices[device.id] = device;
          _status = 'Select a monitor to connect';
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _status = 'Scan failed: $error');
      },
    );
  }

  void _connect(DiscoveredDevice device) {
    _connectionSubscription?.cancel();
    _telemetrySubscription?.cancel();
    setState(() {
      _connectedDeviceId = device.id;
      _telemetry = null;
      _status = 'Connecting to ${device.name.isEmpty ? device.id : device.name}…';
    });
    _connectionSubscription = _ble.connect(device.id).listen(
      (update) {
        if (!mounted) return;
        setState(() => _status = 'Connection: ${update.connectionState.name}');
        if (update.connectionState == DeviceConnectionState.connected) {
          _subscribe(device.id);
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _status = 'Connection failed: $error');
      },
    );
  }

  void _subscribe(String deviceId) {
    _telemetrySubscription?.cancel();
    _telemetrySubscription = _ble.telemetry(deviceId).listen(
      (packet) {
        if (mounted) setState(() => _telemetry = packet);
      },
      onError: (Object error) {
        if (mounted) setState(() => _status = 'Telemetry failed: $error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Battery Monitor')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Scan for monitors'),
          ),
          const SizedBox(height: 16),
          ..._devices.values.map(
            (device) => Card(
              child: ListTile(
                leading: const Icon(Icons.battery_charging_full),
                title: Text(device.name.isEmpty ? 'Battery Monitor' : device.name),
                subtitle: Text('RSSI ${device.rssi} dBm'),
                trailing: FilledButton(
                  onPressed: () => _connect(device),
                  child: const Text('Connect'),
                ),
              ),
            ),
          ),
          if (_connectedDeviceId != null) ...[
            const SizedBox(height: 16),
            _TelemetryCard(telemetry: _telemetry),
          ],
        ],
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({required this.telemetry});

  final BinaryTelemetryV1? telemetry;

  @override
  Widget build(BuildContext context) {
    if (telemetry == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Waiting for live telemetry…'),
        ),
      );
    }
    final values = <String, String>{
      'Voltage': _format(telemetry!.validVoltageVolts, 'V'),
      'Current': _format(telemetry!.validCurrentAmps, 'A'),
      'Power': _format(telemetry!.validPowerWatts, 'W'),
      'Temperature': _format(telemetry!.validTemperatureCelsius, '°C'),
      'Session charge': _format(telemetry!.netAmpHours, 'Ah'),
      'Session energy': _format(telemetry!.netWattHours, 'Wh'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live telemetry', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...values.entries.map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key),
                trailing: Text(entry.value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(double? value, String unit) {
    return value == null ? 'Unavailable' : '${value.toStringAsFixed(2)} $unit';
  }
}
