# beacons_flutter

A Flutter plugin for scanning BLE (Bluetooth Low Energy) beacons on Android and iOS.

## Features

**Cross-platform support**
- Android (API 21+)
- iOS (13.0+) WIP (On iOS not working for iBeacons, because you hace to specify the UUID)

**Beacon detection**
- iBeacon (Apple)
- Eddystone (Google) - UID, URL, TLM, EID
- AltBeacon
- Generic BLE devices

**Detailed information**
- RSSI (signal strength)
- TX Power
- Manufacturer Data
- Service UUIDs
- Service Data
- Data in hexadecimal and ASCII format

## Installation

Add this to your `pubspec.yaml` file:

```yaml
dependencies:
  beacons_flutter:
    path: ../
```

## Setup

### Android

Add the required permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest>
    <!-- Permissions for Bluetooth LE scanning -->
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    
    <!-- Permissions for Android 12+ (API 31+) -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    
    <!-- Location permissions required for BLE scanning -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    
    <!-- Declare that the app uses Bluetooth LE -->
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
</manifest>
```

### iOS

Permissions are already configured in the plugin, but make sure your `Info.plist` includes:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth access to scan for nearby beacons</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app needs Bluetooth access to scan for nearby beacons</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to scan for nearby BLE beacons</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs location access to scan for nearby BLE beacons</string>
```

## Usage

```dart
import 'package:beacons_flutter/beacons_flutter.dart';

class BeaconScannerPage extends StatefulWidget {
  @override
  _BeaconScannerPageState createState() => _BeaconScannerPageState();
}

class _BeaconScannerPageState extends State<BeaconScannerPage> {
  final BeaconsFlutter _beaconsPlugin = BeaconsFlutter();
  StreamSubscription<Map<String, dynamic>>? _scanSubscription;
  
  @override
  void initState() {
    super.initState();
    _listenToScanResults();
  }
  
  void _listenToScanResults() {
    _scanSubscription = _beaconsPlugin.scanResults.listen((device) {
      print('Beacon found: ${device['name']}');
      print('RSSI: ${device['rssi']} dBm');
      print('Manufacturer Data: ${device['manufacturerData']}');
    });
  }
  
  Future<void> startScanning() async {
    // Check permissions
    final hasPermissions = await _beaconsPlugin.checkPermissions();
    if (!hasPermissions) {
      print('No Bluetooth or Location permissions');
      return;
    }
    
    // Start scanning
    final success = await _beaconsPlugin.startScan();
    if (success) {
      print('Scan started');
    }
  }
  
  Future<void> stopScanning() async {
    await _beaconsPlugin.stopScan();
    print('Scan stopped');
  }
  
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _beaconsPlugin.stopScan();
    super.dispose();
  }
}
```

## Beacon data structure

Each detected beacon contains:

```dart
{
  'id': 'UUID or MAC address',
  'name': 'Device name',
  'rssi': -65,  // Signal strength
  'txPower': -59,  // Transmission power
  'connectable': true,
  'serviceUuids': ['0000feaa-0000-1000-8000-00805f9b34fb'],
  'manufacturerData': {
    '76': '02 15 uuid major minor txpower'  // Apple iBeacon
  },
  'serviceData': {
    '0000feaa-0000-1000-8000-00805f9b34fb': '00 ...'  // Eddystone
  },
  'isEddystone': false
}
```

## API

### `checkPermissions()`
Checks if the required permissions are granted.

```dart
final hasPermissions = await beaconsPlugin.checkPermissions();
```

### `startScan()`
Starts scanning for BLE beacons.

```dart
final success = await beaconsPlugin.startScan();
```

### `stopScan()`
Stops scanning for beacons.

```dart
await beaconsPlugin.stopScan();
```

### `scanResults`
Stream that emits detected beacons.

```dart
beaconsPlugin.scanResults.listen((device) {
  // Process detected beacon
});
```

## Example

Run the included example:

```bash
cd example
flutter run
```

## Requirements

- Flutter SDK: >=3.3.0
- Dart SDK: ^3.9.2
- Android: API 21+ (Android 5.0+)
- iOS: 13.0+

## License

MIT License

## Author

Gerard Gutiérrez Flotats

## Contributing

Contributions are welcome. Please open an issue or pull request.
