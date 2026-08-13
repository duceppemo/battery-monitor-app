import 'dart:async';

import 'package:battery_monitor_app/app_build_info.dart';
import 'package:battery_monitor_app/ble/battery_monitor_ble.dart';
import 'package:battery_monitor_app/ble/ble_permission_gate.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class MonitorDashboard extends StatefulWidget {
  MonitorDashboard({
    super.key,
    BatteryMonitorBleClient? ble,
    BlePermissionGate? permissionGate,
  })  : ble = ble ?? BatteryMonitorBle(),
        permissionGate = permissionGate ?? PlatformBlePermissionGate();

  final BatteryMonitorBleClient ble;
  final BlePermissionGate permissionGate;

  @override
  State<MonitorDashboard> createState() => _MonitorDashboardState();
}

class _MonitorDashboardState extends State<MonitorDashboard> {
  final Map<String, DiscoveredDevice> _devices = {};

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<BinaryTelemetryV1>? _telemetrySubscription;
  BinaryTelemetryV1? _telemetry;
  String _status = 'Ready to scan';
  DeviceConnectionState? _connectionState;
  String? _selectedDeviceId;

  bool get _isConnected =>
      _connectionState == DeviceConnectionState.connected;
  bool get _isConnecting =>
      _connectionState == DeviceConnectionState.connecting;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _telemetrySubscription?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    final permission = await widget.permissionGate.request();
    if (!mounted) return;
    if (permission != BlePermissionState.ready) {
      setState(() {
        _status = permission == BlePermissionState.permanentlyDenied
            ? 'Bluetooth permission is blocked. Enable it in app settings.'
            : 'Bluetooth permission is required to scan for monitors.';
      });
      return;
    }

    await _scanSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _devices.clear();
      _selectedDeviceId = null;
      _connectionState = null;
      _telemetry = null;
      _status = 'Scanning for Battery Monitor...';
    });
    _scanSubscription = widget.ble.scan().listen(
      (device) {
        if (!mounted || _connectionState != null) return;
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

  Future<void> _connect(DiscoveredDevice device) async {
    await _connectionSubscription?.cancel();
    await _telemetrySubscription?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (!mounted) return;

    setState(() {
      _selectedDeviceId = device.id;
      _connectionState = DeviceConnectionState.connecting;
      _telemetry = null;
      _status = 'Connecting to ${device.name.isEmpty ? device.id : device.name}...';
    });
    _connectionSubscription = widget.ble.connect(device.id).listen(
      (update) {
        if (!mounted) return;
        setState(() {
          _connectionState = update.connectionState;
          _status = switch (update.connectionState) {
            DeviceConnectionState.connected =>
              'Connected - subscribing to live telemetry...',
            DeviceConnectionState.connecting => 'Connecting...',
            DeviceConnectionState.disconnecting => 'Disconnecting...',
            DeviceConnectionState.disconnected => 'Disconnected',
          };
        });
        if (update.connectionState == DeviceConnectionState.connected) {
          _subscribe(device.id);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _connectionState = DeviceConnectionState.disconnected;
          _status = 'Connection failed: $error';
        });
      },
    );
  }

  void _subscribe(String deviceId) {
    _telemetrySubscription?.cancel();
    _telemetrySubscription = widget.ble.telemetry(deviceId).listen(
      (packet) {
        if (mounted) {
          setState(() {
            _telemetry = packet;
            _status = 'Connected - receiving live telemetry';
          });
        }
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
            onPressed: _isConnecting ? null : _scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Scan for monitors'),
          ),
          const SizedBox(height: 16),
          ..._devices.values.map((device) => _deviceCard(context, device)),
          if (_isConnected) ...[
            const SizedBox(height: 16),
            _TelemetryCard(telemetry: _telemetry),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              AppBuildInfo.label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(BuildContext context, DiscoveredDevice device) {
    final isSelected = device.id == _selectedDeviceId;
    final isDisabled = isSelected && (_isConnecting || _isConnected);
    final label = isSelected && _isConnected
        ? 'Connected'
        : isSelected && _isConnecting
        ? 'Connecting...'
        : 'Connect';

    return Card(
      child: ListTile(
        leading: Icon(
          Icons.battery_charging_full,
          color: isSelected && _isConnected
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        title: Text(device.name.isEmpty ? 'Battery Monitor' : device.name),
        subtitle: Text('RSSI ${device.rssi} dBm'),
        trailing: FilledButton(
          onPressed: isDisabled ? null : () => _connect(device),
          child: Text(label),
        ),
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
          child: Text('Waiting for live telemetry...'),
        ),
      );
    }
    final values = <String, String>{
      'Voltage': _format(telemetry!.validVoltageVolts, 'V'),
      'Current': _format(telemetry!.validCurrentAmps, 'A'),
      'Power': _format(telemetry!.validPowerWatts, 'W'),
      'Temperature': _format(telemetry!.validTemperatureCelsius, 'deg C'),
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
