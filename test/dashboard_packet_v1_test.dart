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
}
