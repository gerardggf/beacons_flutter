import 'dart:async';

import 'beacons_flutter_platform_interface.dart';

export 'beacons_flutter_platform_interface.dart';

/// Main class to interact with the beacons_flutter plugin
class BeaconsFlutter {
  /// Get the platform-specific implementation
  BeaconsFlutterPlatform get _platform => BeaconsFlutterPlatform.instance;

  /// Stream of scan results
  Stream<Map<String, dynamic>> get scanResults => _platform.scanResults;

  /// Start scanning for beacons
  ///
  /// [iBeaconUUIDs] - Optional list of iBeacon UUIDs to scan for on iOS.
  /// iOS requires specific UUIDs to detect iBeacons via Core Location.
  /// On Android, this parameter is ignored as BLE scanning detects all beacons.
  ///
  /// Example:
  /// ```dart
  /// // Scan for all beacons (Eddystone, AltBeacon, generic BLE)
  /// await beaconsPlugin.startScan();
  ///
  /// // Scan including specific iBeacons on iOS
  /// await beaconsPlugin.startScan(
  ///   iBeaconUUIDs: ['E2C56DB5-DFFB-48D2-B060-D0F5A71096E0']
  /// );
  /// ```
  ///
  /// Returns `true` if the scan started successfully, `false` otherwise.
  Future<bool> startScan({List<String>? iBeaconUUIDs}) {
    return _platform.startScan(iBeaconUUIDs: iBeaconUUIDs);
  }

  /// Stop scanning for beacons
  ///
  /// Returns `true` if the scan stopped successfully, `false` otherwise.
  Future<bool> stopScan() {
    return _platform.stopScan();
  }

  /// Check if required permissions are granted
  ///
  /// Returns `true` if all required permissions are granted, `false` otherwise.
  /// Required permissions include:
  /// - Bluetooth (BLUETOOTH, BLUETOOTH_ADMIN on older Android versions)
  /// - Bluetooth Scan and Connect (on Android 12+)
  /// - Location (ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION)
  Future<bool> checkPermissions() {
    return _platform.checkPermissions();
  }

  /// Request required permissions
  ///
  /// Returns `true` if all required permissions are granted after request, `false` otherwise.
  /// This will show the native permission dialogs on both Android and iOS.
  Future<bool> requestPermissions() {
    return _platform.requestPermissions();
  }

  /// Get platform version (legacy method for compatibility)
  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }
}
