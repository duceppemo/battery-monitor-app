import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:battery_monitor_app/app_build_info.dart';
import 'package:battery_monitor_app/models/alarm_settings.dart';
import 'package:battery_monitor_app/ble/battery_monitor_ble.dart';
import 'package:battery_monitor_app/ble/ble_permission_gate.dart';
import 'package:battery_monitor_app/models/binary_telemetry_v1.dart';
import 'package:battery_monitor_app/models/dashboard_packet_v1.dart';
import 'package:battery_monitor_app/models/session_log.dart';
import 'package:battery_monitor_app/models/telemetry_presentation_filter.dart';
import 'package:battery_monitor_app/updates/github_release_checker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:share_plus/share_plus.dart';

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
  final SessionLog _sessionLog = SessionLog();
  final TelemetryPresentationFilter _presentationFilter =
      TelemetryPresentationFilter();
  final AlarmSettingsStore _alarmStore = AlarmSettingsStore();
  final GithubReleaseChecker _releaseChecker = GithubReleaseChecker();
  AlarmSettings _alarmSettings = const AlarmSettings();
  List<String> _alarmMessages = const [];
  Set<String> _recordedAlarmMessages = <String>{};
  bool _alarmSettingsDirty = false;
  final List<int> _calibrationSamples = [];
  final _resistanceController = TextEditingController(text: '15.000');
  final _offsetController = TextEditingController(text: '0.000');
  final _gainController = TextEditingController(text: '1.000000');
  final _referenceCurrentController = TextEditingController();
  final _lowVoltageAlarmController = TextEditingController(text: '3.000');
  final _highVoltageAlarmController = TextEditingController(text: '4.250');
  final _currentAlarmController = TextEditingController(text: '5.000');
  final _temperatureAlarmController = TextEditingController(text: '60.0');

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<BinaryTelemetryV1>? _telemetrySubscription;
  StreamSubscription<DashboardPacketV1>? _dashboardSubscription;
  BinaryTelemetryV1? _telemetry;
  PresentedTelemetry? _presentedTelemetry;
  String _status = 'Ready to scan';
  DeviceConnectionState? _connectionState;
  String? _selectedDeviceId;
  String? _deviceInfo;
  bool _calibrationFieldsInitialized = false;
  bool _finalShuntPresetSelected = false;
  int? _lastMonitorUptimeSeconds;
  Timer? _demoTimer;
  bool _demoMode = false;
  int _demoSequence = 0;
  String _appUpdateStatus = 'Check for a newer Battery Monitor app release.';
  GithubRelease? _firmwareRelease;
  Uint8List? _downloadedFirmware;
  String? _downloadedFirmwareVersion;
  bool _firmwareTransferInProgress = false;
  double _firmwareTransferProgress = 0;
  String _firmwareTransferStatus =
      'Connect to a monitor to read its firmware version before checking for updates.';

  bool get _isConnected => _connectionState == DeviceConnectionState.connected;
  bool get _isConnecting =>
      _connectionState == DeviceConnectionState.connecting;
  bool get _canControl => _isConnected && _selectedDeviceId != null;
  bool get _showMonitor => _isConnected || _demoMode;
  bool get _supportsBleOta => _deviceInfo?.contains('ota1') ?? false;
  bool get _supportsAcknowledgedControls =>
      _deviceInfo?.contains('control1') ?? false;
  String get _monitorFirmwareVersion =>
      RegExp(r'FW=([^;]+)').firstMatch(_deviceInfo ?? '')?.group(1) ??
      'Reading...';
  String? get _connectedFirmwareVersion =>
      RegExp(r'FW=([^;]+)').firstMatch(_deviceInfo ?? '')?.group(1);
  bool get _firmwareUpdateAvailable {
    final release = _firmwareRelease;
    final installed = _connectedFirmwareVersion;
    return release != null &&
        installed != null &&
        GithubReleaseChecker.isNewer(release.version, installed);
  }

  bool get _downloadedFirmwareCanInstall {
    final downloaded = _downloadedFirmwareVersion;
    final installed = _connectedFirmwareVersion;
    // The normal updater is deliberately forward-only. Recovery or downgrade
    // needs an explicit future flow, not an enabled button by accident.
    return downloaded != null &&
        installed != null &&
        GithubReleaseChecker.isNewer(downloaded, installed);
  }

  void _clearDownloadedFirmware({String? status}) {
    _downloadedFirmware = null;
    _downloadedFirmwareVersion = null;
    if (status != null) _firmwareTransferStatus = status;
  }

  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _telemetrySubscription?.cancel();
    _dashboardSubscription?.cancel();
    _demoTimer?.cancel();
    _resistanceController.dispose();
    _offsetController.dispose();
    _gainController.dispose();
    _referenceCurrentController.dispose();
    _lowVoltageAlarmController.dispose();
    _highVoltageAlarmController.dispose();
    _currentAlarmController.dispose();
    _temperatureAlarmController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    _stopDemo();
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
      _clearDownloadedFirmware(
        status:
            'Scanning. Download firmware again after connecting to a monitor.',
      );
      _devices.clear();
      _selectedDeviceId = null;
      _connectionState = null;
      _telemetry = null;
      _presentedTelemetry = null;
      _presentationFilter.reset();
      _recordedAlarmMessages = <String>{};
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

  Future<void> _checkAppUpdates() async {
    setState(() => _appUpdateStatus = 'Checking for a newer app release...');
    try {
      final release = await _releaseChecker.latestAppRelease();
      final status = release == null
          ? 'App: no release published yet'
          : GithubReleaseChecker.isNewer(release.version, AppBuildInfo.version)
              ? 'App update: v${release.version} available'
              : GithubReleaseChecker.isNewer(
                  AppBuildInfo.version,
                  release.version,
                )
                  ? 'Installed app v${AppBuildInfo.version} is newer than the latest published v${release.version}'
                  : 'App v${AppBuildInfo.version} is up to date';
      if (mounted) setState(() => _appUpdateStatus = status);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _appUpdateStatus =
            'App update check failed: ${GithubReleaseChecker.describeRequestError(error)}');
      }
    }
  }

  Future<void> _checkFirmwareUpdates() async {
    final installed = _connectedFirmwareVersion;
    if (!_canControl || installed == null) {
      setState(() => _firmwareTransferStatus =
          'Connect to a monitor and wait for its firmware version before checking for updates.');
      return;
    }

    setState(() => _firmwareTransferStatus =
        'Checking for a newer monitor firmware release...');
    try {
      final release = await _releaseChecker.latestFirmwareRelease();
      if (!mounted) return;
      setState(() {
        _firmwareRelease = release;
        if (release == null) {
          _firmwareTransferStatus =
              'No monitor firmware release is published yet.';
        } else if (release.firmwareAsset == null) {
          _firmwareTransferStatus =
              'Firmware release v${release.version} has no installable OTA .bin asset.';
        } else if (GithubReleaseChecker.isNewer(release.version, installed)) {
          _firmwareTransferStatus =
              'Firmware update available: v$installed → v${release.version}. Download it to prepare BLE installation.';
        } else {
          _firmwareTransferStatus =
              'Monitor firmware v$installed is up to date.';
        }
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _firmwareTransferStatus =
            'Firmware update check failed: ${GithubReleaseChecker.describeRequestError(error)}');
      }
    }
  }

  Future<GithubRelease?> _getFirmwareRelease() async {
    if (_firmwareRelease != null) return _firmwareRelease;
    final release = await _releaseChecker.latestFirmwareRelease();
    if (mounted) setState(() => _firmwareRelease = release);
    return release;
  }

  Future<void> _downloadFirmware() async {
    try {
      setState(() => _firmwareTransferStatus =
          'Downloading the firmware release. Keep this app open.');
      final release = await _getFirmwareRelease();
      final asset = release?.firmwareAsset;
      if (release == null || asset == null) {
        throw StateError('No installable firmware .bin is published yet.');
      }
      final installed = _connectedFirmwareVersion;
      if (installed != null &&
          !GithubReleaseChecker.isNewer(release.version, installed)) {
        if (mounted) {
          setState(() => _firmwareTransferStatus =
              'Monitor firmware v$installed is already current; no download is needed.');
        }
        return;
      }
      final firmware = await _releaseChecker.download(asset);
      if (!mounted) return;
      setState(() {
        _downloadedFirmware = firmware;
        _downloadedFirmwareVersion = release.version;
        _firmwareTransferStatus =
            'v${release.version} downloaded (${(firmware.length / 1024).toStringAsFixed(0)} KiB). Ready to install over BLE.';
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _firmwareTransferStatus =
            'Download failed: ${GithubReleaseChecker.describeRequestError(error)}');
      }
    }
  }

  Future<void> _installFirmware() async {
    final deviceId = _selectedDeviceId;
    final firmware = _downloadedFirmware;
    if (deviceId == null || firmware == null || !_canControl) return;
    if (!_supportsBleOta) {
      _showMessage(
          'This monitor firmware does not yet support BLE OTA. Use the Web Dashboard once to install an OTA-capable version.');
      return;
    }
    if (!_downloadedFirmwareCanInstall) {
      _showMessage(
          'This downloaded firmware is older than the connected monitor. Download the appropriate update first.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Install firmware over Bluetooth?'),
        content: Text(
          'The downloaded image (${(firmware.length / 1024).toStringAsFixed(0)} KiB) will replace the monitor firmware. Keep the phone near the monitor, leave this app open, and do not remove monitor power.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _firmwareTransferInProgress = true;
      _firmwareTransferProgress = 0;
      _firmwareTransferStatus = 'Transferring firmware over BLE...';
    });
    try {
      await widget.ble.installFirmware(
        deviceId,
        firmware,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _firmwareTransferProgress = progress;
              _firmwareTransferStatus =
                  'Transferring firmware: ${(progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _firmwareTransferProgress = 1;
          _firmwareTransferStatus =
              'Firmware verified. The monitor is restarting; reconnect in a few seconds.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
            () => _firmwareTransferStatus = 'Firmware transfer failed: $error');
      }
    } finally {
      if (mounted) setState(() => _firmwareTransferInProgress = false);
    }
  }

  void _startDemo() {
    _demoTimer?.cancel();
    setState(() {
      _demoMode = true;
      _telemetry = null;
      _presentedTelemetry = null;
      _presentationFilter.reset();
      _recordedAlarmMessages = <String>{};
      _dashboard = DashboardSnapshot()
        ..hasState = true
        ..sensorOk = true
        ..displayOn = true
        ..inaConfigured = true
        ..inaReadbackValid = true
        ..calibrationStored = false
        ..shuntResistanceOhms = 0.015
        ..currentGain = 1.0;
      _status = 'Demo monitor - simulated telemetry';
      _sessionLog.recordEvent('Demo monitor started');
    });
    _demoTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final seconds = ++_demoSequence / 2.0;
      final voltage = 3.35 - seconds * 0.0004 + math.sin(seconds / 8) * 0.012;
      final current = 0.42 + math.sin(seconds / 3) * 0.14;
      final power = voltage * current;
      final temperature = 28 + math.sin(seconds / 20) * 1.5;
      final telemetry = BinaryTelemetryV1.simulated(
        sequence: _demoSequence,
        voltageVolts: voltage,
        currentAmps: current,
        powerWatts: power,
        temperatureCelsius: temperature,
        netAmpHours: seconds * current / 3600,
        netWattHours: seconds * power / 3600,
      );
      setState(() {
        _telemetry = telemetry;
        _presentedTelemetry = _presentationFilter.update(telemetry);
        _sessionLog.add(telemetry);
        _dashboard
          ..voltageMinVolts = _min(_dashboard.voltageMinVolts, voltage)
          ..voltageMaxVolts = _max(_dashboard.voltageMaxVolts, voltage)
          ..currentMinAmps = _min(_dashboard.currentMinAmps, current)
          ..currentMaxAmps = _max(_dashboard.currentMaxAmps, current)
          ..powerMinWatts = _min(_dashboard.powerMinWatts, power)
          ..powerMaxWatts = _max(_dashboard.powerMaxWatts, power)
          ..temperatureMinCelsius =
              _min(_dashboard.temperatureMinCelsius, temperature)
          ..temperatureMaxCelsius =
              _max(_dashboard.temperatureMaxCelsius, temperature)
          ..uptimeSeconds = seconds.round()
          ..successfulSamples = _demoSequence
          ..lastShuntVoltageNanoVolts = (current * 0.015 * 1e9).round()
          ..shuntVoltageValid = true;
        _alarmMessages = _alarmSettings.evaluate(telemetry, _dashboard);
        _recordAlarmTransitions();
      });
    });
  }

  void _stopDemo() {
    _demoTimer?.cancel();
    _demoTimer = null;
    if (mounted && _demoMode) {
      setState(() {
        _demoMode = false;
        _sessionLog.recordEvent('Demo monitor stopped');
      });
    }
  }

  static double _min(double? old, double value) =>
      old == null ? value : math.min(old, value);
  static double _max(double? old, double value) =>
      old == null ? value : math.max(old, value);

  Future<void> _connect(DiscoveredDevice device) async {
    await _connectionSubscription?.cancel();
    await _telemetrySubscription?.cancel();
    await _dashboardSubscription?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (!mounted) return;

    setState(() {
      _clearDownloadedFirmware(
        status:
            'Disconnected. Download firmware again after connecting to a monitor.',
      );
      _selectedDeviceId = device.id;
      _connectionState = DeviceConnectionState.connecting;
      _telemetry = null;
      _presentedTelemetry = null;
      _presentationFilter.reset();
      _dashboard = DashboardSnapshot();
      _lastMonitorUptimeSeconds = null;
      _recordedAlarmMessages = <String>{};
      _deviceInfo = null;
      _calibrationFieldsInitialized = false;
      _status =
          'Connecting to ${device.name.isEmpty ? device.id : device.name}...';
    });
    _connectionSubscription = widget.ble.connect(device.id).listen(
      (update) {
        if (!mounted) return;
        setState(() {
          _connectionState = update.connectionState;
          if (update.connectionState == DeviceConnectionState.disconnected) {
            _clearDownloadedFirmware(
              status:
                  'Connection lost. Download firmware again after reconnecting to a monitor.',
            );
            _sessionLog.recordEvent('Monitor disconnected');
            _recordedAlarmMessages = <String>{};
          } else if (update.connectionState ==
              DeviceConnectionState.connected) {
            _sessionLog.recordEvent(
              'Monitor connected',
              detail: device.name.isEmpty ? device.id : device.name,
            );
          }
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
          _readDeviceInfo(device.id);
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _clearDownloadedFirmware(
              status:
                  'Connection failed. Download firmware again after reconnecting to a monitor.',
            );
            _connectionState = DeviceConnectionState.disconnected;
            _status = 'Connection failed: $error';
            _sessionLog.recordEvent('Connection failed', detail: '$error');
          });
        }
      },
    );
  }

  Future<void> _disconnect() async {
    await _telemetrySubscription?.cancel();
    await _dashboardSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _telemetrySubscription = null;
    _dashboardSubscription = null;
    _connectionSubscription = null;
    if (!mounted) return;
    setState(() {
      _clearDownloadedFirmware(
        status:
            'Disconnected. Download firmware again after connecting to a monitor.',
      );
      _connectionState = DeviceConnectionState.disconnected;
      _selectedDeviceId = null;
      _telemetry = null;
      _presentedTelemetry = null;
      _presentationFilter.reset();
      _deviceInfo = null;
      _dashboard = DashboardSnapshot();
      _lastMonitorUptimeSeconds = null;
      _recordedAlarmMessages = <String>{};
      _sessionLog.recordEvent('Monitor disconnected by user');
      _status = 'Disconnected — scan to connect to a monitor.';
    });
  }

  Future<void> _readDeviceInfo(String deviceId) async {
    try {
      final value = await widget.ble.deviceInfo(deviceId);
      if (mounted && _selectedDeviceId == deviceId) {
        setState(() => _deviceInfo = value);
      }
    } on Object {
      // Firmware predating this characteristic remains compatible.
      if (mounted && _selectedDeviceId == deviceId) {
        setState(() => _deviceInfo = 'Unavailable (update firmware)');
      }
    }
  }

  Future<void> _loadAlarms() async {
    final settings = await _alarmStore.load();
    if (!mounted) return;
    setState(() {
      _alarmSettings = settings;
      _lowVoltageAlarmController.text = settings.lowVoltage.toStringAsFixed(3);
      _highVoltageAlarmController.text =
          settings.highVoltage.toStringAsFixed(3);
      _currentAlarmController.text =
          settings.maxAbsoluteCurrent.toStringAsFixed(3);
      _temperatureAlarmController.text =
          settings.maxTemperature.toStringAsFixed(1);
    });
  }

  Future<void> _saveAlarms() async {
    final low = double.tryParse(_lowVoltageAlarmController.text);
    final high = double.tryParse(_highVoltageAlarmController.text);
    final current = double.tryParse(_currentAlarmController.text);
    final temperature = double.tryParse(_temperatureAlarmController.text);
    if (low == null ||
        high == null ||
        current == null ||
        temperature == null ||
        !low.isFinite ||
        !high.isFinite ||
        !current.isFinite ||
        !temperature.isFinite ||
        low < 0 ||
        low >= high ||
        high > 100 ||
        current <= 0 ||
        current > 200 ||
        temperature < -40 ||
        temperature > 125) {
      _showMessage('Check alarm thresholds.');
      return;
    }
    final settings = _alarmSettings.copyWith(
      lowVoltage: low,
      highVoltage: high,
      maxAbsoluteCurrent: current,
      maxTemperature: temperature,
    );
    if (_canControl && _selectedDeviceId != null) {
      if (!_supportsAcknowledgedControls) {
        _showMessage(
            'Update the monitor firmware before changing device alarm settings.');
        return;
      }
      final flags = (settings.lowVoltageEnabled ? 1 : 0) |
          (settings.highVoltageEnabled ? 2 : 0) |
          (settings.currentEnabled ? 4 : 0) |
          (settings.temperatureEnabled ? 8 : 0) |
          (settings.sensorHealthEnabled ? 16 : 0);
      final bytes = ByteData(13)
        ..setUint8(0, 6)
        ..setUint8(1, flags)
        ..setUint16(2, (settings.lowVoltage * 1000).round(), Endian.little)
        ..setUint16(4, (settings.highVoltage * 1000).round(), Endian.little)
        ..setInt32(9, (settings.maxTemperature * 10).round(), Endian.little);
      final currentMilliAmps = (settings.maxAbsoluteCurrent * 1000).round();
      bytes.setUint8(6, currentMilliAmps & 0xff);
      bytes.setUint8(7, (currentMilliAmps >> 8) & 0xff);
      bytes.setUint8(8, (currentMilliAmps >> 16) & 0xff);
      try {
        await widget.ble
            .sendControl(_selectedDeviceId!, bytes.buffer.asUint8List());
      } on Object catch (error) {
        if (mounted) {
          _showMessage('Monitor did not save alarm settings: $error');
        }
        return;
      }
    }
    await _alarmStore.save(settings);
    if (!mounted) return;
    setState(() {
      _alarmSettings = settings;
      _alarmMessages = _telemetry == null
          ? const []
          : settings.evaluate(_telemetry!, _dashboard);
      _alarmSettingsDirty = false;
    });
    _showMessage(_canControl
        ? 'Alarm settings saved on the monitor and this phone.'
        : 'Alarm settings saved on this phone.');
  }

  void _subscribe(String deviceId) {
    _telemetrySubscription?.cancel();
    _dashboardSubscription?.cancel();
    _telemetrySubscription = widget.ble.telemetry(deviceId).listen(
      (packet) {
        if (mounted) {
          setState(() {
            _telemetry = packet;
            _presentedTelemetry = _presentationFilter.update(packet);
            _sessionLog.add(packet);
            _alarmMessages = _alarmSettings.evaluate(packet, _dashboard);
            _recordAlarmTransitions();
            _status = 'Connected - receiving live telemetry';
          });
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _status = 'Live telemetry failed: $error';
            _sessionLog.recordEvent('Live telemetry failed', detail: '$error');
          });
        }
      },
    );
    _dashboardSubscription = widget.ble.dashboard(deviceId).listen(
      (packet) {
        if (!mounted) return;
        setState(() {
          if (packet.type == DashboardPacketType.state) {
            final uptime = packet.uptimeSeconds;
            final previousUptime = _lastMonitorUptimeSeconds;
            if (previousUptime != null && uptime < previousUptime) {
              _sessionLog.recordEvent(
                'Monitor restart detected',
                detail: 'Uptime reset from ${previousUptime}s to ${uptime}s',
              );
            }
            _lastMonitorUptimeSeconds = uptime;
          }
          _dashboard.update(packet);
          if (packet.type == DashboardPacketType.alarms &&
              !_alarmSettingsDirty) {
            _loadAlarmsFromMonitor();
          }
          if (packet.type == DashboardPacketType.calibration &&
              packet.shuntVoltageValid) {
            _calibrationSamples.add(packet.shuntVoltageNanoVolts);
            if (_calibrationSamples.length > 8) {
              _calibrationSamples.removeAt(0);
            }
          }
          if (_telemetry != null) {
            _alarmMessages = _alarmSettings.evaluate(_telemetry!, _dashboard);
          }
          _recordAlarmTransitions();
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
        if (mounted) {
          setState(() {
            _status = 'Dashboard data failed: $error';
            _sessionLog.recordEvent('Dashboard data failed', detail: '$error');
          });
        }
      },
    );
  }

  Future<void> _sendControl(List<int> command, String successMessage) async {
    final deviceId = _selectedDeviceId;
    if (!_canControl || deviceId == null) return;
    if (!_supportsAcknowledgedControls) {
      _showMessage(
          'Update the monitor firmware before using acknowledged controls.');
      return;
    }
    try {
      await widget.ble.sendControl(deviceId, command);
      if (mounted) _showMessage(successMessage);
    } on Object catch (error) {
      if (mounted) _showMessage('Command failed: $error');
    }
  }

  void _captureZero() {
    final average = _stableCalibrationAverage();
    if (average == null) {
      _showMessage('Wait for four stable shunt samples before capturing zero.');
      return;
    }
    _offsetController.text = (average / 1000).toStringAsFixed(3);
    _showMessage('Stable zero average captured. Save calibration to apply it.');
  }

  void _calculateReferenceGain() {
    final current = double.tryParse(_referenceCurrentController.text);
    final resistanceMilliOhms = double.tryParse(_resistanceController.text);
    final offsetMicroVolts = double.tryParse(_offsetController.text);
    final sampleNanoVolts = _stableCalibrationAverage();
    if (current == null ||
        resistanceMilliOhms == null ||
        offsetMicroVolts == null ||
        sampleNanoVolts == null ||
        !current.isFinite ||
        !resistanceMilliOhms.isFinite ||
        !offsetMicroVolts.isFinite) {
      _showMessage(
          'Enter a reference current and wait for four stable shunt samples.');
      return;
    }
    final adjustedShuntVolts = sampleNanoVolts / 1e9 - offsetMicroVolts / 1e6;
    if (!adjustedShuntVolts.isFinite || adjustedShuntVolts == 0) {
      _showMessage(
          'Reference shunt voltage is zero; gain cannot be calculated.');
      return;
    }
    final gain = current * (resistanceMilliOhms / 1000) / adjustedShuntVolts;
    if (!gain.isFinite || gain < 0.5 || gain > 1.5) {
      _showMessage(
          'Calculated gain is outside the permitted 0.5 to 1.5 range.');
      return;
    }
    _gainController.text = gain.toStringAsFixed(6);
    _showMessage('Reference gain calculated. Save calibration to apply it.');
  }

  int? _stableCalibrationAverage() {
    if (_calibrationSamples.length < 4) return null;
    final total = _calibrationSamples.fold<int>(0, (sum, value) => sum + value);
    final average = total / _calibrationSamples.length;
    final minimum = _calibrationSamples.reduce((a, b) => a < b ? a : b);
    final maximum = _calibrationSamples.reduce((a, b) => a > b ? a : b);
    final allowedSpread = average.abs() * 0.02 + 100;
    return maximum - minimum <= allowedSpread ? average.round() : null;
  }

  String _calibrationSampleStatus() {
    if (_calibrationSamples.isEmpty) return 'Waiting for shunt samples';
    final total = _calibrationSamples.fold<int>(0, (sum, value) => sum + value);
    final average = total / _calibrationSamples.length;
    final minimum = _calibrationSamples.reduce((a, b) => a < b ? a : b);
    final maximum = _calibrationSamples.reduce((a, b) => a > b ? a : b);
    final stable = _stableCalibrationAverage() != null;
    return '${_calibrationSamples.length}/8 samples | '
        '${(average / 1000).toStringAsFixed(3)} uV avg | '
        '${((maximum - minimum) / 1000).toStringAsFixed(3)} uV spread | '
        '${stable ? 'stable' : 'settling'}';
  }

  Future<void> _saveCalibration() async {
    final resistanceMilliOhms = double.tryParse(_resistanceController.text);
    final offsetMicroVolts = double.tryParse(_offsetController.text);
    final gain = double.tryParse(_gainController.text);
    if (resistanceMilliOhms == null ||
        offsetMicroVolts == null ||
        gain == null ||
        !resistanceMilliOhms.isFinite ||
        !offsetMicroVolts.isFinite ||
        !gain.isFinite ||
        resistanceMilliOhms < 0.05 ||
        resistanceMilliOhms > 100 ||
        offsetMicroVolts.abs() > 10000 ||
        gain < 0.5 ||
        gain > 1.5) {
      _showMessage('Enter valid calibration values.');
      return;
    }
    if (_finalShuntPresetSelected) {
      final confirmed = await _confirmFinalShuntSave();
      if (!confirmed) return;
    }
    final payload = ByteData(13)
      ..setUint8(0, 4)
      ..setUint32(1, (resistanceMilliOhms * 1000).round(), Endian.little)
      ..setInt32(5, (offsetMicroVolts * 1000).round(), Endian.little)
      ..setInt32(9, (gain * 1e6).round(), Endian.little);
    await _sendControl(payload.buffer.asUint8List(),
        'Calibration saved; session values were reset.');
  }

  Future<bool> _confirmFinalShuntSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply final-shunt calibration?'),
        content: const Text(
          'This saves 0.500 mOhm calibration to the monitor and resets its session values. '
          'Only continue after the final Kelvin shunt is installed and its sense wires are verified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _usePrototypeShuntPreset() {
    setState(() {
      _resistanceController.text = '15.000';
      _offsetController.text = '0.000';
      _gainController.text = '1.000000';
      _finalShuntPresetSelected = false;
    });
    _showMessage(
        '15 mOhm prototype preset loaded. Save calibration to apply it.');
  }

  void _useFinalShuntPreset() {
    setState(() {
      _resistanceController.text = '0.500';
      _offsetController.text = '0.000';
      _gainController.text = '1.000000';
      _finalShuntPresetSelected = true;
    });
    _showMessage(
        '0.5 mOhm / 100 A / 50 mV preset loaded. Verify wiring before saving.');
  }

  Future<void> _showShuntChecklist() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Final Kelvin shunt checklist'),
        content: const Text(
          '1. Put the shunt in the battery negative path.\n\n'
          '2. Connect INA228 VIN+ to the battery/source side Kelvin sense terminal.\n\n'
          '3. Connect INA228 VIN- to the load side Kelvin sense terminal.\n\n'
          '4. Keep sense wires twisted and separate from the high-current cables.\n\n'
          '5. Start with no load, capture zero, then verify with a small known load before higher current.\n\n'
          'This orientation reports discharge current as positive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startTestSession() async {
    final name = TextEditingController();
    final chemistry = TextEditingController();
    final capacity = TextEditingController();
    final notes = TextEditingController();
    final metadata = await showDialog<TestSessionMetadata>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start new test session'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Test name'),
              ),
              TextField(
                controller: chemistry,
                decoration:
                    const InputDecoration(labelText: 'Battery chemistry'),
              ),
              TextField(
                controller: capacity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Rated capacity (Ah, optional)'),
              ),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              TestSessionMetadata(
                name: name.text,
                chemistry: chemistry.text,
                ratedCapacityAh: double.tryParse(capacity.text.trim()),
                notes: notes.text,
              ),
            ),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    name.dispose();
    chemistry.dispose();
    capacity.dispose();
    notes.dispose();
    if (metadata == null || !mounted) return;
    setState(() {
      _sessionLog.start(metadata);
      _recordedAlarmMessages = <String>{};
    });
    _showMessage('Test session "${metadata.displayName}" started.');
  }

  void _finishTestSession() {
    if (_sessionLog.entries.isEmpty) {
      _showMessage('Collect live telemetry before finishing a test session.');
      return;
    }
    final summary = _sessionLog.finish();
    setState(() {});
    _showTestSessionSummary(summary);
  }

  Future<void> _showTestSessionSummary(TestSessionSummary summary) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${summary.metadata.displayName} summary'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _valueRow('Duration', _formatDuration(summary.duration)),
                _valueRow('Samples', '${summary.sampleCount}'),
                _valueRow('Events', '${summary.eventCount}'),
                _valueRow(
                    'Voltage',
                    '${_format(summary.voltageStartVolts, 'V')} → '
                        '${_format(summary.voltageEndVolts, 'V')}'),
                _valueRow(
                    'Current range',
                    _minMax(
                        summary.currentMinAmps, summary.currentMaxAmps, 'A')),
                _valueRow('Net charge', _format(summary.netAmpHours, 'Ah')),
                _valueRow('Net energy', _format(summary.netWattHours, 'Wh')),
                if (summary.dischargedCapacityFraction != null)
                  _valueRow(
                    'Rated capacity used',
                    '${(summary.dischargedCapacityFraction! * 100).toStringAsFixed(1)}%',
                  ),
                if (summary.estimatedRemainingCapacityAh != null)
                  _valueRow(
                    'Estimated remaining',
                    '${summary.estimatedRemainingCapacityAh!.toStringAsFixed(3)} Ah '
                        '(${summary.estimatedRemainingCapacityPercent!.toStringAsFixed(1)}%)',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Future<void> _shareSessionLog() async {
    if (_sessionLog.entries.isEmpty) {
      _showMessage('Collect live telemetry before exporting a CSV file.');
      return;
    }
    final stem = _sessionLog.metadata.displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final fileName = 'battery-monitor-${stem.isEmpty ? 'session' : stem}.csv';
    final csv = _sessionLog.toCsv(deviceInfo: _deviceInfo);
    try {
      await SharePlus.instance.share(ShareParams(
        title: '${_sessionLog.metadata.displayName} session log',
        files: [
          XFile.fromData(
            utf8.encode(csv),
            mimeType: 'text/csv',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
      ));
    } on Object catch (error) {
      if (mounted) _showMessage('CSV export failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Battery Monitor')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status, style: Theme.of(context).textTheme.bodyLarge),
          if (_isConnected && !_demoMode)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Monitor firmware v$_monitorFirmwareVersion',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_showMonitor) ...[
            const SizedBox(height: 12),
            _liveSection(context),
            const SizedBox(height: 12),
            _alarmSection(context),
            const SizedBox(height: 12),
            _sessionSection(context),
            const SizedBox(height: 12),
            _logSection(context),
            const SizedBox(height: 12),
            _sensorSection(context),
            const SizedBox(height: 12),
            _statusSection(context),
            const SizedBox(height: 12),
            _shuntSetupSection(context),
            const SizedBox(height: 12),
            _calibrationSection(context),
          ],
          const SizedBox(height: 12),
          _connectionAndUpdatesSection(context),
          const SizedBox(height: 12),
          _firmwareUpdateSection(context),
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

  Widget _connectionAndUpdatesSection(BuildContext context) {
    final isShowingMonitor = _showMonitor;
    return Card(
      child: ExpansionTile(
        // Changing this key only when the monitor view appears/disappears
        // gives a connected session a compact default without preventing the
        // user from opening the panel again.
        key: ValueKey('connection-tools-$isShowingMonitor'),
        initiallyExpanded: !isShowingMonitor,
        leading: Icon(isShowingMonitor
            ? Icons.bluetooth_connected
            : Icons.bluetooth_searching),
        title: const Text('Connection & app update'),
        subtitle: Text(isShowingMonitor
            ? 'Connected — tap to scan, switch monitor, or check for an app update'
            : 'Scan for a monitor or start the demo'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _isConnecting ? null : _scan,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Scan for monitors'),
              ),
              OutlinedButton.icon(
                onPressed: _demoMode ? _stopDemo : _startDemo,
                icon: Icon(_demoMode
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline),
                label:
                    Text(_demoMode ? 'Stop demo monitor' : 'Try demo monitor'),
              ),
              OutlinedButton.icon(
                onPressed: _checkAppUpdates,
                icon: const Icon(Icons.system_update_outlined),
                label: const Text('Check app update'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_appUpdateStatus,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          ..._devices.values.map((device) => _deviceCard(context, device)),
        ],
      ),
    );
  }

  Widget _deviceCard(BuildContext context, DiscoveredDevice device) {
    final isSelected = device.id == _selectedDeviceId;
    final isDisconnect = isSelected && _isConnected;
    final label = isDisconnect
        ? 'Disconnect'
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
        trailing: isDisconnect
            ? OutlinedButton(
                onPressed: _disconnect,
                child: const Text('Disconnect'),
              )
            : FilledButton(
                onPressed:
                    isSelected && _isConnecting ? null : () => _connect(device),
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
    final shown =
        _presentedTelemetry ?? _presentationFilter.update(_telemetry!);
    return _SectionCard(
      title: 'Live values',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Display filter: ${_presentationFilter.mode.label}. Raw values remain in alarms, history, CSV, and Ah/Wh.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<TelemetryFilterMode>(
            segments: TelemetryFilterMode.values
                .map((mode) => ButtonSegment<TelemetryFilterMode>(
                      value: mode,
                      label: Text(mode.label),
                    ))
                .toList(growable: false),
            selected: {_presentationFilter.mode},
            onSelectionChanged: (selected) {
              final mode = selected.single;
              setState(() {
                _presentationFilter.select(mode);
                _presentedTelemetry = _presentationFilter.update(_telemetry!);
              });
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricCard(
                  'Voltage',
                  _format(shown.voltageVolts, 'V'),
                  _minMax(_dashboard.voltageMinVolts,
                      _dashboard.voltageMaxVolts, 'V')),
              _MetricCard(
                  'Current',
                  _format(shown.currentAmps, 'A'),
                  _minMax(_dashboard.currentMinAmps, _dashboard.currentMaxAmps,
                      'A')),
              _MetricCard(
                  'Power',
                  _format(shown.powerWatts, 'W'),
                  _minMax(
                      _dashboard.powerMinWatts, _dashboard.powerMaxWatts, 'W')),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _canControl
                ? () => _sendControl(const [1], 'Min/max values reset.')
                : null,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset min/max'),
          ),
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
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _canControl
                  ? () => _sendControl(const [2], 'Session energy reset.')
                  : null,
              icon: const Icon(Icons.energy_savings_leaf_outlined),
              label: const Text('Reset Ah / Wh'),
            ),
          ),
        ],
      ),
    );
  }

  void _loadAlarmsFromMonitor() {
    final flags = _dashboard.deviceAlarmEnabledFlags;
    if (flags == null ||
        _dashboard.deviceAlarmLowVoltage == null ||
        _dashboard.deviceAlarmHighVoltage == null ||
        _dashboard.deviceAlarmMaxCurrent == null ||
        _dashboard.deviceAlarmMaxTemperature == null) {
      return;
    }
    _alarmSettings = AlarmSettings(
      lowVoltageEnabled: (flags & 1) != 0,
      lowVoltage: _dashboard.deviceAlarmLowVoltage!,
      highVoltageEnabled: (flags & 2) != 0,
      highVoltage: _dashboard.deviceAlarmHighVoltage!,
      currentEnabled: (flags & 4) != 0,
      maxAbsoluteCurrent: _dashboard.deviceAlarmMaxCurrent!,
      temperatureEnabled: (flags & 8) != 0,
      maxTemperature: _dashboard.deviceAlarmMaxTemperature!,
      sensorHealthEnabled: (flags & 16) != 0,
    );
    _lowVoltageAlarmController.text =
        _alarmSettings.lowVoltage.toStringAsFixed(3);
    _highVoltageAlarmController.text =
        _alarmSettings.highVoltage.toStringAsFixed(3);
    _currentAlarmController.text =
        _alarmSettings.maxAbsoluteCurrent.toStringAsFixed(3);
    _temperatureAlarmController.text =
        _alarmSettings.maxTemperature.toStringAsFixed(1);
  }

  List<String> get _visibleAlarmMessages {
    final flags = _dashboard.deviceAlarmActiveFlags;
    if (flags == null) return _alarmMessages;
    final messages = <String>[];
    if ((flags & 1) != 0) messages.add('Low voltage');
    if ((flags & 2) != 0) messages.add('High voltage');
    if ((flags & 4) != 0) messages.add('Current limit');
    if ((flags & 8) != 0) messages.add('High temperature');
    if ((flags & 16) != 0) messages.add('INA228 sensor health');
    return messages;
  }

  void _recordAlarmTransitions() {
    final active = _visibleAlarmMessages.toSet();
    for (final alarm in active.difference(_recordedAlarmMessages)) {
      _sessionLog.recordEvent('Alarm active', detail: alarm);
    }
    for (final alarm in _recordedAlarmMessages.difference(active)) {
      _sessionLog.recordEvent('Alarm cleared', detail: alarm);
    }
    _recordedAlarmMessages = active;
  }

  Widget _alarmSection(BuildContext context) => Card(
        color: _visibleAlarmMessages.isEmpty
            ? null
            : Theme.of(context).colorScheme.errorContainer,
        child: ExpansionTile(
          title: Text(_visibleAlarmMessages.isEmpty
              ? 'Alarms: all clear'
              : 'Alarms: ${_visibleAlarmMessages.length} active'),
          subtitle: Text(_visibleAlarmMessages.isEmpty
              ? (_dashboard.deviceAlarmEnabledFlags == null
                  ? 'App-side thresholds are active while connected.'
                  : 'Monitor thresholds active: ${_dashboard.deviceAlarmEnabledFlags == 0 ? 'none enabled' : 'configured'}')
              : _visibleAlarmMessages.join(' | ')),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _alarmToggle(
                'Low voltage',
                _alarmSettings.lowVoltageEnabled,
                (v) => setState(() {
                      _alarmSettings =
                          _alarmSettings.copyWith(lowVoltageEnabled: v);
                      _alarmSettingsDirty = true;
                    })),
            _alarmField(_lowVoltageAlarmController, 'Low voltage (V)'),
            _alarmToggle(
                'High voltage',
                _alarmSettings.highVoltageEnabled,
                (v) => setState(() {
                      _alarmSettings =
                          _alarmSettings.copyWith(highVoltageEnabled: v);
                      _alarmSettingsDirty = true;
                    })),
            _alarmField(_highVoltageAlarmController, 'High voltage (V)'),
            _alarmToggle(
                'Absolute current',
                _alarmSettings.currentEnabled,
                (v) => setState(() {
                      _alarmSettings =
                          _alarmSettings.copyWith(currentEnabled: v);
                      _alarmSettingsDirty = true;
                    })),
            _alarmField(_currentAlarmController, 'Current limit (A)'),
            _alarmToggle(
                'Temperature',
                _alarmSettings.temperatureEnabled,
                (v) => setState(() {
                      _alarmSettings =
                          _alarmSettings.copyWith(temperatureEnabled: v);
                      _alarmSettingsDirty = true;
                    })),
            _alarmField(_temperatureAlarmController, 'Temperature limit (C)'),
            _alarmToggle(
                'INA228 health',
                _alarmSettings.sensorHealthEnabled,
                (v) => setState(() {
                      _alarmSettings =
                          _alarmSettings.copyWith(sensorHealthEnabled: v);
                      _alarmSettingsDirty = true;
                    })),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: _saveAlarms,
                child: const Text('Save alarm settings')),
          ],
        ),
      );

  Widget _alarmToggle(String label, bool value, ValueChanged<bool> changed) =>
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          onChanged: changed);

  Widget _alarmField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        onChanged: (_) => _alarmSettingsDirty = true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );

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

  Widget _logSection(BuildContext context) {
    final entries = _sessionLog.entries;
    final summary = _sessionLog.summary;
    final recentEvents = _sessionLog.events.reversed.take(8).toList();
    return _SectionCard(
      title: 'Test session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _sessionLog.isRecording
                ? '${_sessionLog.metadata.displayName} is recording locally.'
                : '${_sessionLog.metadata.displayName} is complete.',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_sessionLog.metadata.chemistry.trim().isNotEmpty ||
              _sessionLog.metadata.ratedCapacityAh != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (_sessionLog.metadata.chemistry.trim().isNotEmpty)
                  _sessionLog.metadata.chemistry.trim(),
                if (_sessionLog.metadata.ratedCapacityAh != null)
                  '${_sessionLog.metadata.ratedCapacityAh!.toStringAsFixed(3)} Ah rated',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${entries.length} samples stored locally (up to 7,200). '
            'Charts show the latest 120 samples.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _TrendLine(
            label: 'Voltage',
            unit: 'V',
            color: Colors.lightBlue,
            values: entries.map((entry) => entry.voltageVolts).toList(),
          ),
          _TrendLine(
            label: 'Current',
            unit: 'A',
            color: Colors.orange,
            values: entries.map((entry) => entry.currentAmps).toList(),
          ),
          _TrendLine(
            label: 'Power',
            unit: 'W',
            color: Colors.purple,
            values: entries.map((entry) => entry.powerWatts).toList(),
          ),
          const SizedBox(height: 8),
          if (entries.isNotEmpty) ...[
            _valueRow('Captured duration', _formatDuration(summary.duration)),
            _valueRow('Captured net',
                '${_format(summary.netAmpHours, 'Ah')} / ${_format(summary.netWattHours, 'Wh')}'),
            _valueRow('Events', '${summary.eventCount}'),
            if (summary.dischargedCapacityFraction != null) ...[
              const SizedBox(height: 4),
              Text('Capacity progress (app estimate)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: summary.dischargedCapacityFraction!.clamp(0, 1),
              ),
              const SizedBox(height: 4),
              _valueRow(
                'Discharged',
                '${_format(summary.netAmpHours, 'Ah')} '
                    '(${(summary.dischargedCapacityFraction! * 100).toStringAsFixed(1)}% of rated)',
              ),
              _valueRow(
                'Estimated remaining',
                '${summary.estimatedRemainingCapacityAh!.toStringAsFixed(3)} Ah '
                    '(${summary.estimatedRemainingCapacityPercent!.toStringAsFixed(1)}%)',
              ),
            ],
            const SizedBox(height: 8),
          ],
          if (recentEvents.isNotEmpty) ...[
            Text('Event timeline',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final event in recentEvents)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(_formatEventTime(event.recordedAt),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(
                      child: Text(
                        event.detail.isEmpty
                            ? event.type
                            : '${event.type}: ${event.detail}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _startTestSession,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start new test'),
              ),
              OutlinedButton.icon(
                onPressed: entries.isEmpty || !_sessionLog.isRecording
                    ? null
                    : _finishTestSession,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Finish test'),
              ),
              OutlinedButton.icon(
                onPressed: entries.isEmpty ? null : _shareSessionLog,
                icon: const Icon(Icons.ios_share),
                label: const Text('Export CSV'),
              ),
              TextButton.icon(
                onPressed: entries.isEmpty
                    ? null
                    : () => setState(() => _sessionLog.clear()),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear log'),
              ),
            ],
          ),
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
          _valueRow('Firmware', 'v$_monitorFirmwareVersion'),
          _valueRow('Device', _deviceInfo ?? 'Reading device information...'),
          const SizedBox(height: 10),
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

  Widget _firmwareUpdateSection(BuildContext context) {
    final release = _firmwareRelease;
    final firmware = _downloadedFirmware;
    final supported = _supportsBleOta;
    final installed = _connectedFirmwareVersion;
    final canCheckFirmware =
        _canControl && installed != null && !_firmwareTransferInProgress;
    final canDownloadUpdate = !_firmwareTransferInProgress &&
        firmware == null &&
        _firmwareUpdateAvailable &&
        release?.firmwareAsset != null;
    return _SectionCard(
      title: 'Monitor firmware update',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_firmwareUpdateSummary(release, installed)),
          const SizedBox(height: 6),
          Text(
            _firmwareTransferStatus,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_firmwareTransferInProgress) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _firmwareTransferProgress),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: firmware != null
                    ? null
                    : canDownloadUpdate
                        ? _downloadFirmware
                        : canCheckFirmware
                            ? _checkFirmwareUpdates
                            : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(firmware == null
                    ? release == null
                        ? 'Check for updates'
                        : _firmwareUpdateAvailable
                            ? 'Download v${release.version}'
                            : installed == null
                                ? 'Connect to check updates'
                                : 'Check for updates'
                    : 'v${_downloadedFirmwareVersion ?? release?.version ?? '?'} downloaded'),
              ),
              FilledButton.icon(
                onPressed: firmware == null ||
                        !_canControl ||
                        !supported ||
                        !_downloadedFirmwareCanInstall ||
                        _firmwareTransferInProgress
                    ? null
                    : _installFirmware,
                icon: const Icon(Icons.bluetooth_connected),
                label: const Text('Install via BLE'),
              ),
            ],
          ),
          if (_isConnected && !supported) ...[
            const SizedBox(height: 8),
            Text(
              'Connected monitor does not advertise BLE OTA yet. Web upload remains available for this one-time bootstrap.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  String _firmwareUpdateSummary(GithubRelease? release, String? installed) {
    if (installed == null) {
      return 'Connect a monitor to read its installed firmware version.';
    }
    if (release == null) {
      return 'Monitor firmware v$installed. Check for updates to compare versions.';
    }
    return _firmwareUpdateAvailable
        ? 'Update available: v$installed → v${release.version}'
        : 'Monitor firmware v$installed is up to date.';
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
          Text(_calibrationSampleStatus(),
              style: Theme.of(context).textTheme.bodySmall),
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

  Widget _shuntSetupSection(BuildContext context) {
    final activeResistance = _dashboard.shuntResistanceOhms;
    return Card(
      child: ExpansionTile(
        title: const Text('Shunt setup'),
        subtitle: Text(_finalShuntPresetSelected
            ? 'Final 0.5 mOhm preset staged - not yet saved'
            : 'Current active: ${activeResistance == null ? 'waiting for device' : '${(activeResistance * 1000).toStringAsFixed(3)} mOhm'}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Incoming target: 100 A / 50 mV Kelvin shunt = 0.500 mOhm. '
            'Loading a preset only updates the calibration form; Save calibration is the explicit write to the monitor.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _usePrototypeShuntPreset,
                child: const Text('Use 15 mOhm prototype'),
              ),
              FilledButton.tonal(
                onPressed: _useFinalShuntPreset,
                child: const Text('Stage 0.5 mOhm final shunt'),
              ),
              TextButton.icon(
                onPressed: _showShuntChecklist,
                icon: const Icon(Icons.checklist_outlined),
                label: const Text('Wiring checklist'),
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
    return _formatDuration(Duration(seconds: seconds));
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  static String _formatEventTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    String part(int value) => value.toString().padLeft(2, '0');
    return '${part(local.hour)}:${part(local.minute)}:${part(local.second)}';
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
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
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

class _TrendLine extends StatelessWidget {
  const _TrendLine({
    required this.label,
    required this.unit,
    required this.color,
    required this.values,
  });

  final String label;
  final String unit;
  final Color color;
  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final recent =
        values.length > 120 ? values.sublist(values.length - 120) : values;
    final finite = recent.whereType<double>().toList();
    final range = finite.isEmpty
        ? 'Waiting for data'
        : '${finite.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)} to '
            '${finite.reduce((a, b) => a > b ? a : b).toStringAsFixed(3)} $unit';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: $range', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          SizedBox(
            height: 58,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(values: recent, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values, required this.color});

  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      border,
    );
    final finite = values.whereType<double>().toList();
    if (finite.length < 2 || size.width <= 0 || size.height <= 0) return;
    var minimum = finite.reduce((a, b) => a < b ? a : b);
    var maximum = finite.reduce((a, b) => a > b ? a : b);
    if (minimum == maximum) {
      minimum -= 1;
      maximum += 1;
    }
    final path = Path();
    var hasPoint = false;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value == null) {
        hasPoint = false;
        continue;
      }
      final x =
          values.length == 1 ? 0.0 : index * size.width / (values.length - 1);
      final y =
          size.height - ((value - minimum) / (maximum - minimum) * size.height);
      if (hasPoint) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        hasPoint = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
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
