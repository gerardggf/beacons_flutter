import 'package:flutter_test/flutter_test.dart';
import 'package:beacons_flutter/beacons_flutter_platform_interface.dart';
import 'package:beacons_flutter/beacons_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBeaconsFlutterPlatform
    with MockPlatformInterfaceMixin
    implements BeaconsFlutterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> checkPermissions() {
    throw UnimplementedError();
  }

  @override
  Stream<Map<String, dynamic>> get scanResults => throw UnimplementedError();

  @override
  Future<bool> startScan() {
    throw UnimplementedError();
  }

  @override
  Future<bool> stopScan() {
    throw UnimplementedError();
  }
}

void main() {
  final BeaconsFlutterPlatform initialPlatform =
      BeaconsFlutterPlatform.instance;

  test('$MethodChannelBeaconsFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBeaconsFlutter>());
  });

  test('getPlatformVersion', () async {});
}
