import 'dart:typed_data';

enum FirmwareUpdateState { idle, receiving, verified, error }

class FirmwareUpdateStatus {
  const FirmwareUpdateStatus({
    required this.state,
    required this.receivedBytes,
    required this.expectedBytes,
    required this.errorCode,
  });

  final FirmwareUpdateState state;
  final int receivedBytes;
  final int expectedBytes;
  final int errorCode;

  factory FirmwareUpdateStatus.decode(List<int> value) {
    if (value.length != 12 || value[0] != 1) {
      throw FormatException('Unexpected firmware update status packet');
    }
    final bytes = Uint8List.fromList(value);
    final data = ByteData.sublistView(bytes);
    final state = switch (value[1]) {
      0 => FirmwareUpdateState.idle,
      1 => FirmwareUpdateState.receiving,
      2 => FirmwareUpdateState.verified,
      _ => FirmwareUpdateState.error,
    };
    return FirmwareUpdateStatus(
      state: state,
      receivedBytes: data.getUint32(2, Endian.little),
      expectedBytes: data.getUint32(6, Endian.little),
      errorCode: value[10],
    );
  }

  String get errorDescription => switch (errorCode) {
        1 => 'update start was rejected',
        2 => 'a transfer frame was out of sequence',
        3 => 'flash write failed',
        4 => 'image checksum did not match',
        5 => 'firmware image verification failed',
        _ => 'unknown update error',
      };
}
