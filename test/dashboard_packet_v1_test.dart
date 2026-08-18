import 'dart:typed_data';

import 'package:battery_monitor_app/models/dashboard_packet_v1.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges extrema and directional-energy dashboard pages', () {
    final extrema = <int>[
      0x11,
      0xd0, 0x0c, // 3.280 V minimum.
      0xe4, 0x0c, // 3.300 V maximum.
      0xec, 0xff, 0xff, // -20 mA minimum.
      0x7d, 0x00, 0x00, // 125 mA maximum.
      0x38, 0xff, 0xff, // -200 mW minimum.
      0x90, 0x01, 0x00, // 400 mW maximum.
      0x1c, 0x1d, // 28 to 29 C.
      0x0f, // All extrema valid.
    ];
    final energy = Uint8List(20);
    energy[0] = 0x12;
    ByteData.sublistView(energy)
      ..setInt32(1, 1234, Endian.little)
      ..setInt32(5, 234, Endian.little)
      ..setInt32(9, 5678, Endian.little)
      ..setInt32(13, 678, Endian.little);

    final snapshot = DashboardSnapshot()
      ..update(DashboardPacketV1.decode(extrema))
      ..update(DashboardPacketV1.decode(energy));

    expect(snapshot.voltageMinVolts, 3.28);
    expect(snapshot.voltageMaxVolts, 3.3);
    expect(snapshot.currentMinAmps, -0.02);
    expect(snapshot.currentMaxAmps, 0.125);
    expect(snapshot.powerMaxWatts, 0.4);
    expect(snapshot.temperatureMinCelsius, 28);
    expect(snapshot.dischargedAmpHours, 1.234);
    expect(snapshot.chargedWattHours, 0.678);
  });

  test('rejects a malformed dashboard page', () {
    expect(() => DashboardPacketV1.decode(const [0x11]), throwsFormatException);
  });

  test('decodes a Wi-Fi station status dashboard page', () {
    final wifi = Uint8List(20);
    wifi[0] = 0x17;
    wifi[1] = 0x07; // configured, connected, mDNS ready.
    wifi[2] = 192;
    wifi[3] = 168;
    wifi[4] = 68;
    wifi[5] = 57;

    final snapshot = DashboardSnapshot()..update(DashboardPacketV1.decode(wifi));

    expect(snapshot.wifiStationConfigured, isTrue);
    expect(snapshot.wifiStationConnected, isTrue);
    expect(snapshot.wifiMdnsReady, isTrue);
    expect(snapshot.wifiStationIp, '192.168.68.57');
  });

  test('omits the station IP when not connected', () {
    final wifi = Uint8List(20);
    wifi[0] = 0x17;
    wifi[1] = 0x01; // configured, but not yet connected.

    final snapshot = DashboardSnapshot()..update(DashboardPacketV1.decode(wifi));

    expect(snapshot.wifiStationConfigured, isTrue);
    expect(snapshot.wifiStationConnected, isFalse);
    expect(snapshot.wifiStationIp, isNull);
  });

  test('decodes a synced, discharging state-of-charge dashboard page', () {
    final soc = Uint8List(20);
    soc[0] = 0x18;
    soc[1] = 0x03; // known + discharging.
    ByteData.sublistView(soc)
      ..setUint16(2, 725, Endian.little) // 72.5%.
      ..setUint32(4, 3600, Endian.little) // 1 hour to empty.
      ..setUint32(8, 100000, Endian.little) // 100 Ah capacity.
      ..setUint16(12, 14400, Endian.little) // 14.4 V charged.
      ..setUint16(14, 350, Endian.little) // 35.0% deepest discharge.
      ..setUint16(16, 12, Endian.little) // 12 full-charge cycles.
      ..setUint16(18, 280, Endian.little); // 28.0% average depth.

    final snapshot = DashboardSnapshot()..update(DashboardPacketV1.decode(soc));

    expect(snapshot.socKnown, isTrue);
    expect(snapshot.socHasTimeToEmpty, isTrue);
    expect(snapshot.socPercent, 72.5);
    expect(snapshot.socTimeToEmptySeconds, 3600);
    expect(snapshot.socCapacityAh, 100.0);
    expect(snapshot.socChargedVoltage, 14.4);
    expect(snapshot.socDeepestDischargePercent, 35.0);
    expect(snapshot.socFullChargeCycles, 12);
    expect(snapshot.socAverageDischargeDepthPercent, 28.0);
  });

  test('omits average discharge depth when there are no cycles yet', () {
    final soc = Uint8List(20);
    soc[0] = 0x18;
    soc[1] = 0x01; // known, not discharging.
    ByteData.sublistView(soc)
      ..setUint16(16, 0, Endian.little) // 0 cycles.
      ..setUint16(18, 999, Endian.little); // garbage average; must be ignored.

    final snapshot = DashboardSnapshot()..update(DashboardPacketV1.decode(soc));

    expect(snapshot.socFullChargeCycles, 0);
    expect(snapshot.socAverageDischargeDepthPercent, isNull);
  });

  test('omits state-of-charge percent and time-to-empty when not synced', () {
    final soc = Uint8List(20);
    soc[0] = 0x18;
    soc[1] = 0x00; // not synced, not discharging.

    final snapshot = DashboardSnapshot()..update(DashboardPacketV1.decode(soc));

    expect(snapshot.socKnown, isFalse);
    expect(snapshot.socHasTimeToEmpty, isFalse);
    expect(snapshot.socPercent, isNull);
    expect(snapshot.socTimeToEmptySeconds, isNull);
  });

  test('decodes a tripped load-protection dashboard page', () {
    final protection = Uint8List(20);
    protection[0] = 0x19;
    protection[1] = 0x05; // enabled + tripped, relay not engaged.
    protection[2] = 0x01; // tripped on low voltage.
    protection[3] = 0x01; // still breaching low voltage right now.
    ByteData.sublistView(protection)
      ..setUint16(4, 3000, Endian.little) // 3.000 V threshold.
      ..setUint16(6, 200, Endian.little); // 20.0% threshold.

    final snapshot =
        DashboardSnapshot()..update(DashboardPacketV1.decode(protection));

    expect(snapshot.protectionEnabled, isTrue);
    expect(snapshot.protectionRelayEngaged, isFalse);
    expect(snapshot.protectionTripped, isTrue);
    expect(snapshot.protectionTripFlags, 1);
    expect(snapshot.protectionBreachFlags, 1);
    expect(snapshot.protectionLowVoltageThreshold, 3.0);
    expect(snapshot.protectionLowSocPercentThreshold, 20.0);
  });

  test('decodes a disabled, connected load-protection dashboard page', () {
    final protection = Uint8List(20);
    protection[0] = 0x19;
    protection[1] = 0x02; // disabled, relay engaged (connected), not tripped.

    final snapshot =
        DashboardSnapshot()..update(DashboardPacketV1.decode(protection));

    expect(snapshot.protectionEnabled, isFalse);
    expect(snapshot.protectionRelayEngaged, isTrue);
    expect(snapshot.protectionTripped, isFalse);
    expect(snapshot.protectionTripFlags, 0);
    expect(snapshot.protectionBreachFlags, 0);
  });
}
