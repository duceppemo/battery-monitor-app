import 'dart:typed_data';

enum ControlResult { idle, applied, rejected, failed, unknown }

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
      // A result code this app version does not know (newer firmware).
      // Surfacing it as a value lets the pending command fail with a
      // readable message instead of an unhandled stream error.
      _ => ControlResult.unknown,
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
        ControlResult.unknown =>
          'returned a result this app version does not recognize',
      };
}
