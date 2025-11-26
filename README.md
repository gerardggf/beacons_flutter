# beacons_flutter

A Flutter plugin for scanning BLE (Bluetooth Low Energy) beacons on Android and iOS.

## Features

**Cross-platform support**
- Android (API 21+)
- iOS (13.0+)

**Beacon detection**
- iBeacon (Apple) - iOS requires UUIDs to be specified in advance
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

Add the required permissions in `ios/Runner/Info.plist`:

```xml
<!-- Permisos para Bluetooth -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth access to scan for nearby beacons</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app needs Bluetooth access to scan for nearby beacons</string>

<!-- Permisos para Ubicación - ALL are required -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to scan for nearby BLE beacons</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs continuous location access to detect beacons even when not using the app</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>This app needs continuous location access to detect beacons in the background</string>

<!-- Background modes -->
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>location</string>
</array>
```

**⚠️ Important for iOS:**
- **iBeacon detection requires UUIDs**: iOS cannot discover iBeacons without knowing their UUIDs in advance. You must specify them when starting the scan.
- **Location "Always" permission**: For best results with BLE scanning, request "Always" location permission.
- **App must be in foreground**: iOS heavily restricts BLE scanning in background mode.

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
      // Request permissions
      final granted = await _beaconsPlugin.requestPermissions();
      if (!granted) {
        print('Permissions denied');
        return;
      }
    }
    
    // Start scanning
    // ⚠️ iOS: If you have iBeacons, you MUST specify their UUIDs
    // Eddystone and AltBeacon will be detected automatically
    final success = await _beaconsPlugin.startScan(
      iBeaconUUIDs: [
        'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',  // Replace with your iBeacon UUIDs
        // Add more UUIDs if you have multiple iBeacons
      ],
    );
    
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

### `requestPermissions()`
Requests the required permissions from the user.

```dart
final granted = await beaconsPlugin.requestPermissions();
```

### `startScan({List<String>? iBeaconUUIDs})`
Starts scanning for BLE beacons.

```dart
// Scan for all beacons (Eddystone, AltBeacon, generic BLE)
await beaconsPlugin.startScan();

// On iOS: Include iBeacon UUIDs to detect iBeacons
await beaconsPlugin.startScan(
  iBeaconUUIDs: ['E2C56DB5-DFFB-48D2-B060-D0F5A71096E0'],
);
```

**Parameters:**
- `iBeaconUUIDs` (optional): List of iBeacon UUIDs to monitor on iOS. Required for iBeacon detection on iOS.

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

## iOS Limitations

iOS has specific limitations compared to Android:

| Feature | Android | iOS |
|---------|---------|-----|
| Discover iBeacons without UUID | ✅ Yes | ❌ No - UUIDs must be specified |
| Detect Eddystone | ✅ Yes | ✅ Yes (as BLE device) |
| Detect AltBeacon | ✅ Yes | ✅ Yes (as BLE device) |
| Background scanning | ✅ Extensive | ⚠️ Very limited |
| Discover UUIDs | ✅ Yes | ❌ No |

**Why iOS requires UUIDs for iBeacons:**
- Apple's CoreLocation framework requires you to specify which beacon UUIDs you want to monitor
- This is a privacy and battery optimization feature
- You cannot "scan" for unknown iBeacon UUIDs on iOS

**How to get iBeacon UUIDs:**
1. Use an Android device with this plugin to discover the UUID
2. Use beacon configuration apps provided by beacon manufacturers
3. Use third-party beacon scanner apps

**Workaround for iOS:**
- Eddystone and AltBeacon are detected as regular BLE devices, so they work without UUIDs
- Only iBeacon protocol has this UUID requirement

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
