import 'package:battery_monitor_app/models/control_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes an applied control result with its request ID', () {
    final status = ControlStatus.decode(const [1, 4, 0x34, 0x12, 1, 0]);

    expect(status.command, 4);
    expect(status.requestId, 0x1234);
    expect(status.result, ControlResult.applied);
  });

  test('rejects malformed control result packets', () {
    expect(() => ControlStatus.decode(const [1, 4]), throwsFormatException);
    expect(
      () => ControlStatus.decode(const [1, 4, 0, 0, 99, 0]),
      throwsFormatException,
    );
  });

  test('accepts the characteristic idle value', () {
    final status = ControlStatus.decode(const [1, 0, 0, 0, 0, 0]);

    expect(status.result, ControlResult.idle);
  });
}
