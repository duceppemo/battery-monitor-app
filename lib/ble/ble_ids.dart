import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

abstract final class BleIds {
  static final service = Uuid.parse('7d9f0000-9c65-4d3d-bdd5-8f4c6b2e1000');
  static final binaryTelemetry =
      Uuid.parse('7d9f0009-9c65-4d3d-bdd5-8f4c6b2e1000');
  static final dashboard = Uuid.parse('7d9f000a-9c65-4d3d-bdd5-8f4c6b2e1000');
  static final control = Uuid.parse('7d9f000b-9c65-4d3d-bdd5-8f4c6b2e1000');
}
