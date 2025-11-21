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
  /// Returns `true` if the scan started successfully, `false` otherwise.
  Future<bool> startScan() {
    return _platform.startScan();
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

  /// Get platform version (legacy method for compatibility)
  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }
}
