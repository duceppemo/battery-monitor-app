import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum BlePermissionState { ready, denied, permanentlyDenied }

/// Requests only the permissions needed for foreground scanning/connection.
/// Android 11 and older expose BLE scan results behind foreground location;
/// Android 12+ uses the separate Nearby devices permission group instead.
abstract interface class BlePermissionGate {
  Future<BlePermissionState> request();
}

class PlatformBlePermissionGate implements BlePermissionGate {
  PlatformBlePermissionGate({Future<int> Function()? androidSdkVersion})
      : _androidSdkVersion = androidSdkVersion ?? _readAndroidSdkVersion;

  final Future<int> Function() _androidSdkVersion;

  static Future<int> _readAndroidSdkVersion() async =>
      (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  @override
  Future<BlePermissionState> request() async {
    if (!Platform.isAndroid) {
      return BlePermissionState.ready;
    }

    // Ask only for what this OS version actually gates BLE on. Requesting
    // the legacy location permission on Android 12+ meant a stale
    // "permanently denied" answer to it blocked scanning even though both
    // Nearby devices permissions were granted; on Android 11 and older the
    // Nearby devices permissions do not exist and report granted, so they
    // must not be allowed to vouch for a missing location grant either.
    final sdkInt = await _androidSdkVersion();
    final permissions = sdkInt >= 31
        ? const [Permission.bluetoothScan, Permission.bluetoothConnect]
        : const [Permission.locationWhenInUse];
    final results = await permissions.request();

    if (results.values.any((status) => status.isPermanentlyDenied)) {
      return BlePermissionState.permanentlyDenied;
    }
    return results.values.every((status) => status.isGranted)
        ? BlePermissionState.ready
        : BlePermissionState.denied;
  }
}
