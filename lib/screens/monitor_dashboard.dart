import 'dart:async';
import 'dart:typed_data';

import 'package:battery_monitor_app/app_build_info.dart';
import 'package:battery_monitor_app/ble/battery_monitor_ble.dart';
import 'package:battery_monitor_app/ble/ble_permission_gate.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/dashboard_packet_v1.dart';
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
  DashboardSnapshot _dashboard = DashboardSnapshot();
  final _resistanceController = TextEditingController(text: '15.000');
  final _offsetController = TextEditingController(text: '0.000');
  final _gainController = TextEditingController(text: '1.000000');
  final _referenceCurrentController = TextEditingController();

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<BinaryTelemetryV1>? _telemetrySubscription;
  StreamSubscription<DashboardPacketV1>? _dashboardSubscription;
  BinaryTelemetryV1? _telemetry;
  String _status = 'Ready to scan';
  DeviceConnectionState? _connectionState;
  String? _selectedDeviceId;
  bool _calibrationFieldsInitialized = false;

  bool get _isConnected => _connectionState == DeviceConnectionState.connected;
  bool get _isConnecting =>
      _connectionState == DeviceConnectionState.connecting;
  bool get _canControl => _isConnected && _selectedDeviceId != null;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _telemetrySubscription?.cancel();
    _dashboardSubscription?.cancel();
    _resistanceController.dispose();
    _offsetController.dispose();
    _gainController.dispose();
    _referenceCurrentController.dispose();
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
    await _dashboardSubscription?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (!mounted) return;

    setState(() {
      _selectedDeviceId = device.id;
      _connectionState = DeviceConnectionState.connecting;
      _telemetry = null;
      _dashboard = DashboardSnapshot();
      _calibrationFieldsInitialized = false;
      _status =
          'Connecting to ${device.name.isEmpty ? device.id : device.name}...';
    });
    _connectionSubscription = widget.ble.connect(device.id).listen(
      (update) {
        if (!mounted) return;
        setState(() {
          _connectionState = update.connectionState;
          _status = switch (update.connectionState) {
            DeviceConnectionState.connected =>
              'Connected - subscribing to monitor data...',
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
        if (mounted) {
          setState(() {
            _connectionState = DeviceConnectionState.disconnected;
            _status = 'Connection failed: $error';
          });
        }
      },
    );
  }

  void _subscribe(String deviceId) {
    _telemetrySubscription?.cancel();
    _dashboardSubscription?.cancel();
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
        if (mounted) setState(() => _status = 'Live telemetry failed: $error');
      },
    );
    _dashboardSubscription = widget.ble.dashboard(deviceId).listen(
      (packet) {
        if (!mounted) return;
        setState(() {
          _dashboard.update(packet);
          if (packet.type == DashboardPacketType.calibration &&
              !_calibrationFieldsInitialized) {
            _calibrationFieldsInitialized = true;
            _resistanceController.text =
                (_dashboard.shuntResistanceOhms! * 1000).toStringAsFixed(3);
            _offsetController.text =
                (_dashboard.shuntOffsetVolts! * 1e6).toStringAsFixed(3);
            _gainController.text = _dashboard.currentGain!.toStringAsFixed(6);
          }
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _status = 'Dashboard data failed: $error');
      },
    );
  }

  Future<void> _sendControl(List<int> command, String successMessage) async {
    final deviceId = _selectedDeviceId;
    if (!_canControl || deviceId == null) return;
    try {
      await widget.ble.sendControl(deviceId, command);
      if (mounted) _showMessage(successMessage);
    } on Object catch (error) {
      if (mounted) _showMessage('Command failed: $error');
    }
  }

  void _captureZero() {
    if (!_dashboard.shuntVoltageValid ||
        _dashboard.lastShuntVoltageNanoVolts == null) {
      _showMessage('Wait for a valid shunt-voltage sample first.');
      return;
    }
    _offsetController.text =
        (_dashboard.lastShuntVoltageNanoVolts! / 1000).toStringAsFixed(3);
    _showMessage('Zero offset captured. Save calibration to apply it.');
  }

  void _calculateReferenceGain() {
    final current = double.tryParse(_referenceCurrentController.text);
    final resistanceMilliOhms = double.tryParse(_resistanceController.text);
    final offsetMicroVolts = double.tryParse(_offsetController.text);
    final sampleNanoVolts = _dashboard.lastShuntVoltageNanoVolts;
    if (current == null ||
        resistanceMilliOhms == null ||
        offsetMicroVolts == null ||
        sampleNanoVolts == null ||
        !_dashboard.shuntVoltageValid) {
      _showMessage(
          'Enter a reference current and wait for a valid shunt sample.');
      return;
    }
    final adjustedShuntVolts = sampleNanoVolts / 1e9 - offsetMicroVolts / 1e6;
    if (adjustedShuntVolts == 0) {
      _showMessage(
          'Reference shunt voltage is zero; gain cannot be calculated.');
      return;
    }
    final gain = current * (resistanceMilliOhms / 1000) / adjustedShuntVolts;
    _gainController.text = gain.toStringAsFixed(6);
    _showMessage('Reference gain calculated. Save calibration to apply it.');
  }

  Future<void> _saveCalibration() async {
    final resistanceMilliOhms = double.tryParse(_resistanceController.text);
    final offsetMicroVolts = double.tryParse(_offsetController.text);
    final gain = double.tryParse(_gainController.text);
    if (resistanceMilliOhms == null ||
        offsetMicroVolts == null ||
        gain == null) {
      _showMessage('Enter valid calibration values.');
      return;
    }
    final payload = ByteData(13)
      ..setUint8(0, 4)
      ..setUint32(1, (resistanceMilliOhms * 1000).round(), Endian.little)
      ..setInt32(5, (offsetMicroVolts * 1000).round(), Endian.little)
      ..setInt32(9, (gain * 1e6).round(), Endian.little);
    await _sendControl(payload.buffer.asUint8List(),
        'Calibration saved; session values were reset.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
          const SizedBox(height: 12),
          ..._devices.values.map((device) => _deviceCard(context, device)),
          if (_isConnected) ...[
            const SizedBox(height: 16),
            _liveSection(context),
            const SizedBox(height: 12),
            _sessionSection(context),
            const SizedBox(height: 12),
            _sensorSection(context),
            const SizedBox(height: 12),
            _statusSection(context),
            const SizedBox(height: 12),
            _controlSection(context),
            const SizedBox(height: 12),
            _calibrationSection(context),
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

  Widget _liveSection(BuildContext context) {
    if (_telemetry == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Waiting for live telemetry...'),
        ),
      );
    }
    return _SectionCard(
      title: 'Live values',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MetricCard(
              'Voltage',
              _format(_telemetry!.validVoltageVolts, 'V'),
              _minMax(
                  _dashboard.voltageMinVolts, _dashboard.voltageMaxVolts, 'V')),
          _MetricCard(
              'Current',
              _format(_telemetry!.validCurrentAmps, 'A'),
              _minMax(
                  _dashboard.currentMinAmps, _dashboard.currentMaxAmps, 'A')),
          _MetricCard('Power', _format(_telemetry!.validPowerWatts, 'W'),
              _minMax(_dashboard.powerMinWatts, _dashboard.powerMaxWatts, 'W')),
        ],
      ),
    );
  }

  Widget _sessionSection(BuildContext context) {
    return _SectionCard(
      title: 'Session energy',
      child: Column(
        children: [
          _valueRow('Net charge (discharge +)',
              _format(_telemetry?.netAmpHours, 'Ah')),
          _valueRow('Net energy (discharge +)',
              _format(_telemetry?.netWattHours, 'Wh')),
          const Divider(),
          _valueRow('Discharged',
              '${_format(_dashboard.dischargedAmpHours, 'Ah')}  /  ${_format(_dashboard.dischargedWattHours, 'Wh')}'),
          _valueRow('Charged',
              '${_format(_dashboard.chargedAmpHours, 'Ah')}  /  ${_format(_dashboard.chargedWattHours, 'Wh')}'),
        ],
      ),
    );
  }

  Widget _sensorSection(BuildContext context) {
    return _SectionCard(
      title: 'Sensor details',
      child: Column(
        children: [
          _valueRow('Temperature',
              '${_format(_telemetry?.validTemperatureCelsius, 'deg C')}  ${_minMax(_dashboard.temperatureMinCelsius, _dashboard.temperatureMaxCelsius, 'deg C')}'),
          _valueRow('Shunt voltage',
              '${_formatNanoVolts(_dashboard.lastShuntVoltageNanoVolts)}  ${_minMaxNanoVolts(_dashboard.shuntMinNanoVolts, _dashboard.shuntMaxNanoVolts)}'),
        ],
      ),
    );
  }

  Widget _statusSection(BuildContext context) {
    return _SectionCard(
      title: 'Monitor status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusChip('INA228', _dashboard.sensorOk),
              _StatusChip('Display', _dashboard.displayOn),
              _StatusChip('Wi-Fi AP', _dashboard.wifiAccessPointReady),
              _StatusChip('Config verified', _dashboard.inaReadbackValid),
            ],
          ),
          const SizedBox(height: 8),
          _valueRow('Samples',
              '${_dashboard.successfulSamples ?? '-'} OK / ${_dashboard.failedSamples ?? '-'} failed'),
          _valueRow(
              'INA config',
              _dashboard.inaConfigured
                  ? '${_dashboard.averages ?? '-'} averages, ${_dashboard.conversionTimeMicroseconds ?? '-'} us'
                  : 'Unavailable'),
          _valueRow(
              'I2C registers',
              _dashboard.configRegister == null
                  ? 'Waiting for config data'
                  : '0x${_dashboard.configRegister!.toRadixString(16).padLeft(4, '0')} / 0x${_dashboard.adcConfigRegister!.toRadixString(16).padLeft(4, '0')}'),
          _valueRow('Uptime', _formatUptime(_dashboard.uptimeSeconds)),
        ],
      ),
    );
  }

  Widget _controlSection(BuildContext context) {
    return _SectionCard(
      title: 'Controls',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _canControl
                ? () => _sendControl(const [1], 'Min/max values reset.')
                : null,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset min/max'),
          ),
          OutlinedButton.icon(
            onPressed: _canControl
                ? () => _sendControl(const [2], 'Session energy reset.')
                : null,
            icon: const Icon(Icons.energy_savings_leaf_outlined),
            label: const Text('Reset session'),
          ),
          OutlinedButton.icon(
            onPressed: _canControl
                ? () => _sendControl(const [3], 'Display toggle requested.')
                : null,
            icon: const Icon(Icons.monitor_outlined),
            label: Text(_dashboard.displayOn ? 'Display off' : 'Display on'),
          ),
        ],
      ),
    );
  }

  Widget _calibrationSection(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text('Current calibration'),
        subtitle: Text(_dashboard.calibrationStored
            ? 'Stored calibration active'
            : 'Compile-time default active'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _resistanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Shunt resistance (mOhm)'),
          ),
          TextField(
            controller: _offsetController,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Zero offset (uV)'),
          ),
          TextField(
            controller: _gainController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Current gain'),
          ),
          const SizedBox(height: 8),
          Text(
              'Live shunt: ${_formatNanoVolts(_dashboard.lastShuntVoltageNanoVolts)}'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _canControl ? _captureZero : null,
                child: const Text('Capture zero'),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _referenceCurrentController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration:
                      const InputDecoration(labelText: 'Reference current (A)'),
                ),
              ),
              OutlinedButton(
                onPressed: _canControl ? _calculateReferenceGain : null,
                child: const Text('Calculate gain'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _canControl ? _saveCalibration : null,
                child: const Text('Save calibration'),
              ),
              TextButton(
                onPressed: _canControl
                    ? () => _sendControl(const [5],
                        'Default calibration restored; session values were reset.')
                    : null,
                child: const Text('Restore default'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _valueRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [Expanded(child: Text(label)), Text(value)],
        ),
      );

  static String _format(double? value, String unit) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(3)} $unit';

  static String _minMax(double? min, double? max, String unit) => min == null ||
          max == null
      ? ''
      : '(min ${min.toStringAsFixed(3)}, max ${max.toStringAsFixed(3)} $unit)';

  static String _formatNanoVolts(int? nanoVolts) => nanoVolts == null
      ? 'Unavailable'
      : '${(nanoVolts / 1e6).toStringAsFixed(3)} mV';

  static String _minMaxNanoVolts(int? min, int? max) => min == null ||
          max == null
      ? ''
      : '(min ${(min / 1e6).toStringAsFixed(3)}, max ${(max / 1e6).toStringAsFixed(3)} mV)';

  static String _formatUptime(int? seconds) {
    if (seconds == null) return 'Waiting for status';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    return '${hours}h ${duration.inMinutes.remainder(60)}m';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.detail);
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 155,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.ok);
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          color: ok ? Colors.green : Theme.of(context).colorScheme.error,
          size: 18,
        ),
        label: Text(label),
      );
}
