import 'dart:async';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'beacons_flutter_method_channel.dart';

abstract class BeaconsFlutterPlatform extends PlatformInterface {
  /// Constructs a BeaconsFlutterPlatform.
  BeaconsFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static BeaconsFlutterPlatform _instance = MethodChannelBeaconsFlutter();

  /// The default instance of [BeaconsFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelBeaconsFlutter].
  static BeaconsFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BeaconsFlutterPlatform] when
  /// they register themselves.
  static set instance(BeaconsFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Stream of scan results
  Stream<Map<String, dynamic>> get scanResults {
    throw UnimplementedError('scanResults has not been implemented.');
  }

  /// Start scanning for beacons
  Future<bool> startScan() {
    throw UnimplementedError('startScan() has not been implemented.');
  }

  /// Stop scanning for beacons
  Future<bool> stopScan() {
    throw UnimplementedError('stopScan() has not been implemented.');
  }

  /// Check if required permissions are granted
  Future<bool> checkPermissions() {
    throw UnimplementedError('checkPermissions() has not been implemented.');
  }

  /// Request required permissions
  Future<bool> requestPermissions() {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  /// Get platform version (legacy method)
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
