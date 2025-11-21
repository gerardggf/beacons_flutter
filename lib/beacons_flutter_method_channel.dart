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
        debugPrint("Error de escaneo: ${call.arguments}");
        break;
      case 'onScanStarted':
        debugPrint("Escaneo iniciado nativamente");
        break;
      case 'onScanStopped':
        debugPrint("Escaneo detenido nativamente");
        break;
      default:
        debugPrint('Método desconocido desde nativo: ${call.method}');
    }
  }

  @override
  Future<bool> startScan() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>('startScan');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error al iniciar scan: ${e.message}");
      return false;
    }
  }

  @override
  Future<bool> stopScan() async {
    try {
      final bool? result = await methodChannel.invokeMethod<bool>('stopScan');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("Error al detener scan: ${e.message}");
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
      debugPrint("Error verificando permisos: ${e.message}");
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
