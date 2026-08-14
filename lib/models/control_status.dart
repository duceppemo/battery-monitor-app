import 'dart:typed_data';

enum ControlResult { idle, applied, rejected, failed }

class ControlStatus {
  const ControlStatus({
    required this.command,
    required this.requestId,
    required this.result,
  });

  final int command;
  final int requestId;
  final ControlResult result;

  factory ControlStatus.decode(List<int> value) {
    if (value.length != 6 || value[0] != 1) {
      throw FormatException('Unexpected control status packet');
    }
    final result = switch (value[4]) {
      0 => ControlResult.idle,
      1 => ControlResult.applied,
      2 => ControlResult.rejected,
      3 => ControlResult.failed,
      _ => throw FormatException('Unknown control result ${value[4]}'),
    };
    return ControlStatus(
      command: value[1],
      requestId: ByteData.sublistView(Uint8List.fromList(value))
          .getUint16(2, Endian.little),
      result: result,
    );
  }

  String get description => switch (result) {
        ControlResult.idle => 'idle',
        ControlResult.applied => 'applied',
        ControlResult.rejected => 'rejected because another command is pending',
        ControlResult.failed => 'could not be saved by the monitor',
      };
}
