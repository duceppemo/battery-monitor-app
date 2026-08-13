import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum BlePermissionState { ready, denied, permanentlyDenied }

/// Requests only the permissions needed for foreground scanning/connection.
/// Android 11 and older expose BLE scan results behind foreground location;
/// Android 12+ uses the separate Nearby devices permission group instead.
abstract interface class BlePermissionGate {
  Future<BlePermissionState> request();
}

class PlatformBlePermissionGate implements BlePermissionGate {
  @override
  Future<BlePermissionState> request() async {
    if (!Platform.isAndroid) {
      return BlePermissionState.ready;
    }

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // This is declared only through API 30. On Android 12+ it resolves
      // harmlessly to denied/not-applicable; BLE permissions drive the Nearby
      // devices prompt there.
      Permission.locationWhenInUse,
    ];
    final results = await permissions.request();

    if (results.values.any((status) => status.isPermanentlyDenied)) {
      return BlePermissionState.permanentlyDenied;
    }

    final bluetoothReady =
        results[Permission.bluetoothScan]?.isGranted == true ||
            results[Permission.bluetoothConnect]?.isGranted == true;
    final locationReady =
        results[Permission.locationWhenInUse]?.isGranted == true;
    return bluetoothReady || locationReady
        ? BlePermissionState.ready
        : BlePermissionState.denied;
  }
}
