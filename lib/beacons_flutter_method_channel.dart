import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'beacons_flutter_platform_interface.dart';

/// An implementation of [BeaconsFlutterPlatform] that uses method channels.
class MethodChannelBeaconsFlutter extends BeaconsFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('native_ble_scanner');

  /// Stream controller for scan results
  final StreamController<Map<String, dynamic>> _scanResultController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Constructor that sets up the method call handler
  MethodChannelBeaconsFlutter() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Stream of scan results from native platform
  @override
  Stream<Map<String, dynamic>> get scanResults => _scanResultController.stream;

  /// Handle method calls from native platform
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceFound':
        final Map<dynamic, dynamic> args = call.arguments;
        _scanResultController.add(Map<String, dynamic>.from(args));
        break;
      case 'onScanError':
        debugPrint("Scan error: ${call.arguments}");
        break;
      case 'onScanStarted':
        debugPrint("Scan started natively");
        break;
      case 'onScanStopped':
        debugPrint("Scan stopped natively");
        break;
      default:
        debugPrint('Unknown method from native: ${call.method}');
    }
  }

  @override
  Future<bool> startScan() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>('startScan');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error starting scan: ${e.message}");
      return false;
    }
  }

  @override
  Future<bool> stopScan() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>('stopScan');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error stopping scan: ${e.message}");
      return false;
    }
  }

  @override
  Future<bool> checkPermissions() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>(
        'checkPermissions',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error checking permissions: ${e.message}");
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>(
        'requestPermissions',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error requesting permissions: ${e.message}");
      return false;
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
