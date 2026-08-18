import 'dart:typed_data';

/// Compact 20-byte dashboard pages from the firmware's dashboard BLE
/// characteristic.  Pages are intentionally independent so they remain safe
/// on the baseline BLE ATT payload size.
enum DashboardPacketType {
  extrema,
  energy,
  state,
  calibration,
  shunt,
  alarms,
  wifi,
  stateOfCharge,
  loadProtection,
}

class DashboardPacketV1 {
  DashboardPacketV1._(this.type, this._packet);

  static const packetLength = 20;
  static const _extrema = 0x11;
  static const _energy = 0x12;
  static const _state = 0x13;
  static const _calibration = 0x14;
  static const _shunt = 0x15;
  static const _alarms = 0x16;
  static const _wifi = 0x17;
  static const _stateOfCharge = 0x18;
  static const _loadProtection = 0x19;

  final DashboardPacketType type;
  final Uint8List _packet;

  factory DashboardPacketV1.decode(List<int> bytes) {
    if (bytes.length != packetLength) {
      throw FormatException(
        'Dashboard packet v1 must be $packetLength bytes, got ${bytes.length}.',
      );
    }
    final packet = Uint8List.fromList(bytes);
    final type = switch (packet[0]) {
      _extrema => DashboardPacketType.extrema,
      _energy => DashboardPacketType.energy,
      _state => DashboardPacketType.state,
      _calibration => DashboardPacketType.calibration,
      _shunt => DashboardPacketType.shunt,
      _alarms => DashboardPacketType.alarms,
      _wifi => DashboardPacketType.wifi,
      _stateOfCharge => DashboardPacketType.stateOfCharge,
      _loadProtection => DashboardPacketType.loadProtection,
      final value =>
        throw FormatException('Unknown dashboard packet type $value.'),
    };
    return DashboardPacketV1._(type, packet);
  }

  ByteData get _data => ByteData.sublistView(_packet);
  int _int24(int offset) {
    var value = _packet[offset] |
        (_packet[offset + 1] << 8) |
        (_packet[offset + 2] << 16);
    if ((value & 0x800000) != 0) value |= ~0xffffff;
    return value;
  }

  double get voltageMinVolts => _data.getUint16(1, Endian.little) / 1000.0;
  double get voltageMaxVolts => _data.getUint16(3, Endian.little) / 1000.0;
  double get currentMinAmps => _int24(5) / 1000.0;
  double get currentMaxAmps => _int24(8) / 1000.0;
  double get powerMinWatts => _int24(11) / 1000.0;
  double get powerMaxWatts => _int24(14) / 1000.0;
  double get temperatureMinCelsius => _data.getInt8(17).toDouble();
  double get temperatureMaxCelsius => _data.getInt8(18).toDouble();
  int get extremaValidFlags => _packet[19];

  double get dischargedAmpHours => _data.getInt32(1, Endian.little) / 1000.0;
  double get chargedAmpHours => _data.getInt32(5, Endian.little) / 1000.0;
  double get dischargedWattHours => _data.getInt32(9, Endian.little) / 1000.0;
  double get chargedWattHours => _data.getInt32(13, Endian.little) / 1000.0;
  bool get energyPersistEnabled => _packet[17] != 0;

  int get stateFlags => _packet[1];
  int get sequence => _data.getUint16(2, Endian.little);
  int get uptimeSeconds => _data.getUint32(4, Endian.little);
  int get successfulSamples => _data.getUint32(8, Endian.little);
  int get failedSamples => _data.getUint32(12, Endian.little);
  int get wifiClients => _packet[16];
  int get resetReason => _packet[17];
  int get conversionTimeMicroseconds => _data.getUint16(18, Endian.little);

  bool get calibrationStored => _packet[1] != 0;
  double get shuntResistanceOhms => _data.getUint32(2, Endian.little) / 1e6;
  double get shuntOffsetVolts => _data.getInt32(6, Endian.little) / 1e9;
  double get currentGain => _data.getInt32(10, Endian.little) / 1e6;
  int get shuntVoltageNanoVolts => _data.getInt32(14, Endian.little);
  bool get shuntVoltageValid => _packet[18] != 0;

  int get shuntMinNanoVolts => _data.getInt32(1, Endian.little);
  int get shuntMaxNanoVolts => _data.getInt32(5, Endian.little);
  int get configRegister => _data.getUint16(9, Endian.little);
  int get adcConfigRegister => _data.getUint16(11, Endian.little);
  int get averages => _data.getUint16(13, Endian.little);
  int get shuntConversionTimeMicroseconds => _data.getUint16(15, Endian.little);
  double get shuntTemperatureMinCelsius => _data.getInt8(17).toDouble();
  double get shuntTemperatureMaxCelsius => _data.getInt8(18).toDouble();
  int get shuntFlags => _packet[19];

  int get alarmEnabledFlags => _packet[1];
  int get alarmActiveFlags => _packet[2];
  double get alarmLowVoltage => _data.getUint16(3, Endian.little) / 1000.0;
  double get alarmHighVoltage => _data.getUint16(5, Endian.little) / 1000.0;
  double get alarmMaxCurrent => _int24(7) / 1000.0;
  double get alarmMaxTemperature => _data.getInt32(10, Endian.little) / 10.0;

  bool get wifiStationConfigured => (_packet[1] & 1) != 0;
  bool get wifiStationConnected => (_packet[1] & 2) != 0;
  bool get wifiMdnsReady => (_packet[1] & 4) != 0;
  String get wifiStationIp =>
      '${_packet[2]}.${_packet[3]}.${_packet[4]}.${_packet[5]}';

  bool get socKnown => (_packet[1] & 1) != 0;
  bool get socHasTimeToEmpty => (_packet[1] & 2) != 0;
  double get socPercent => _data.getUint16(2, Endian.little) / 10.0;
  int get socTimeToEmptySeconds => _data.getUint32(4, Endian.little);
  double get socCapacityAh => _data.getUint32(8, Endian.little) / 1000.0;
  double get socChargedVoltage => _data.getUint16(12, Endian.little) / 1000.0;
  double get socDeepestDischargePercent =>
      _data.getUint16(14, Endian.little) / 10.0;
  int get socFullChargeCycles => _data.getUint16(16, Endian.little);
  double get socAverageDischargeDepthPercent =>
      _data.getUint16(18, Endian.little) / 10.0;

  bool get protectionEnabled => (_packet[1] & 1) != 0;
  bool get protectionRelayEngaged => (_packet[1] & 2) != 0;
  bool get protectionTripped => (_packet[1] & 4) != 0;
  int get protectionTripFlags => _packet[2];
  int get protectionBreachFlags => _packet[3];
  double get protectionLowVoltageThreshold =>
      _data.getUint16(4, Endian.little) / 1000.0;
  double get protectionLowSocPercentThreshold =>
      _data.getUint16(6, Endian.little) / 10.0;
}

/// The latest value of each independently rotating dashboard page.
class DashboardSnapshot {
  bool hasState = false;
  double? voltageMinVolts;
  double? voltageMaxVolts;
  double? currentMinAmps;
  double? currentMaxAmps;
  double? powerMinWatts;
  double? powerMaxWatts;
  double? temperatureMinCelsius;
  double? temperatureMaxCelsius;
  double? dischargedAmpHours;
  double? chargedAmpHours;
  double? dischargedWattHours;
  double? chargedWattHours;
  bool energyPersistEnabled = false;
  bool sensorOk = false;
  bool displayOn = true;
  bool inaConfigured = false;
  bool inaReadbackValid = false;
  bool wideShuntRange = false;
  bool wifiAccessPointReady = false;
  bool calibrationStored = false;
  int? uptimeSeconds;
  int? successfulSamples;
  int? failedSamples;
  int? wifiClients;
  int? resetReason;
  int? conversionTimeMicroseconds;
  double? shuntResistanceOhms;
  double? shuntOffsetVolts;
  double? currentGain;
  int? lastShuntVoltageNanoVolts;
  bool shuntVoltageValid = false;
  int? shuntMinNanoVolts;
  int? shuntMaxNanoVolts;
  int? configRegister;
  int? adcConfigRegister;
  int? averages;
  int? deviceAlarmEnabledFlags;
  int? deviceAlarmActiveFlags;
  double? deviceAlarmLowVoltage;
  double? deviceAlarmHighVoltage;
  double? deviceAlarmMaxCurrent;
  double? deviceAlarmMaxTemperature;
  bool wifiStationConfigured = false;
  bool wifiStationConnected = false;
  bool wifiMdnsReady = false;
  String? wifiStationIp;
  bool socKnown = false;
  bool socHasTimeToEmpty = false;
  double? socPercent;
  int? socTimeToEmptySeconds;
  double socCapacityAh = 0;
  double socChargedVoltage = 0;
  double socDeepestDischargePercent = 0;
  int socFullChargeCycles = 0;
  double? socAverageDischargeDepthPercent;
  bool protectionEnabled = false;
  bool protectionRelayEngaged = true;
  bool protectionTripped = false;
  int protectionTripFlags = 0;
  int protectionBreachFlags = 0;
  double protectionLowVoltageThreshold = 0;
  double protectionLowSocPercentThreshold = 0;

  void update(DashboardPacketV1 packet) {
    switch (packet.type) {
      case DashboardPacketType.extrema:
        final flags = packet.extremaValidFlags;
        if ((flags & 1) != 0) {
          voltageMinVolts = packet.voltageMinVolts;
          voltageMaxVolts = packet.voltageMaxVolts;
        }
        if ((flags & 2) != 0) {
          currentMinAmps = packet.currentMinAmps;
          currentMaxAmps = packet.currentMaxAmps;
        }
        if ((flags & 4) != 0) {
          powerMinWatts = packet.powerMinWatts;
          powerMaxWatts = packet.powerMaxWatts;
        }
        if ((flags & 8) != 0) {
          temperatureMinCelsius = packet.temperatureMinCelsius;
          temperatureMaxCelsius = packet.temperatureMaxCelsius;
        }
        break;
      case DashboardPacketType.energy:
        dischargedAmpHours = packet.dischargedAmpHours;
        chargedAmpHours = packet.chargedAmpHours;
        dischargedWattHours = packet.dischargedWattHours;
        chargedWattHours = packet.chargedWattHours;
        energyPersistEnabled = packet.energyPersistEnabled;
        break;
      case DashboardPacketType.state:
        hasState = true;
        final flags = packet.stateFlags;
        sensorOk = (flags & 1) != 0;
        displayOn = (flags & 2) != 0;
        inaConfigured = (flags & 4) != 0;
        inaReadbackValid = (flags & 8) != 0;
        wideShuntRange = (flags & 16) != 0;
        wifiAccessPointReady = (flags & 32) != 0;
        calibrationStored = (flags & 64) != 0;
        uptimeSeconds = packet.uptimeSeconds;
        successfulSamples = packet.successfulSamples;
        failedSamples = packet.failedSamples;
        wifiClients = packet.wifiClients;
        resetReason = packet.resetReason;
        conversionTimeMicroseconds = packet.conversionTimeMicroseconds;
        break;
      case DashboardPacketType.calibration:
        calibrationStored = packet.calibrationStored;
        shuntResistanceOhms = packet.shuntResistanceOhms;
        shuntOffsetVolts = packet.shuntOffsetVolts;
        currentGain = packet.currentGain;
        lastShuntVoltageNanoVolts = packet.shuntVoltageNanoVolts;
        shuntVoltageValid = packet.shuntVoltageValid;
        break;
      case DashboardPacketType.shunt:
        if ((packet.shuntFlags & 1) != 0) {
          shuntMinNanoVolts = packet.shuntMinNanoVolts;
          shuntMaxNanoVolts = packet.shuntMaxNanoVolts;
        }
        configRegister = packet.configRegister;
        adcConfigRegister = packet.adcConfigRegister;
        averages = packet.averages;
        conversionTimeMicroseconds = packet.shuntConversionTimeMicroseconds;
        if ((packet.shuntFlags & 2) != 0) {
          temperatureMinCelsius = packet.shuntTemperatureMinCelsius;
          temperatureMaxCelsius = packet.shuntTemperatureMaxCelsius;
        }
        break;
      case DashboardPacketType.alarms:
        deviceAlarmEnabledFlags = packet.alarmEnabledFlags;
        deviceAlarmActiveFlags = packet.alarmActiveFlags;
        deviceAlarmLowVoltage = packet.alarmLowVoltage;
        deviceAlarmHighVoltage = packet.alarmHighVoltage;
        deviceAlarmMaxCurrent = packet.alarmMaxCurrent;
        deviceAlarmMaxTemperature = packet.alarmMaxTemperature;
        break;
      case DashboardPacketType.wifi:
        wifiStationConfigured = packet.wifiStationConfigured;
        wifiStationConnected = packet.wifiStationConnected;
        wifiMdnsReady = packet.wifiMdnsReady;
        wifiStationIp =
            packet.wifiStationConnected ? packet.wifiStationIp : null;
        break;
      case DashboardPacketType.stateOfCharge:
        socKnown = packet.socKnown;
        socHasTimeToEmpty = packet.socHasTimeToEmpty;
        socPercent = packet.socKnown ? packet.socPercent : null;
        socTimeToEmptySeconds =
            packet.socHasTimeToEmpty ? packet.socTimeToEmptySeconds : null;
        socCapacityAh = packet.socCapacityAh;
        socChargedVoltage = packet.socChargedVoltage;
        socDeepestDischargePercent = packet.socDeepestDischargePercent;
        socFullChargeCycles = packet.socFullChargeCycles;
        socAverageDischargeDepthPercent = packet.socFullChargeCycles > 0
            ? packet.socAverageDischargeDepthPercent
            : null;
        break;
      case DashboardPacketType.loadProtection:
        protectionEnabled = packet.protectionEnabled;
        protectionRelayEngaged = packet.protectionRelayEngaged;
        protectionTripped = packet.protectionTripped;
        protectionTripFlags = packet.protectionTripFlags;
        protectionBreachFlags = packet.protectionBreachFlags;
        protectionLowVoltageThreshold = packet.protectionLowVoltageThreshold;
        protectionLowSocPercentThreshold =
            packet.protectionLowSocPercentThreshold;
        break;
    }
  }
}
