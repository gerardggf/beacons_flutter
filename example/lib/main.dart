import 'package:flutter/material.dart';
import 'dart:async';
import 'package:beacons_flutter/beacons_flutter.dart';

void main() {
  runApp(const BeaconsFlutterExampleApp());
}

class BeaconsFlutterExampleApp extends StatefulWidget {
  const BeaconsFlutterExampleApp({super.key});

  @override
  State<BeaconsFlutterExampleApp> createState() =>
      _BeaconsFlutterExampleAppState();
}

class _BeaconsFlutterExampleAppState extends State<BeaconsFlutterExampleApp> {
  final BeaconsFlutter _beaconsPlugin = BeaconsFlutter();
  final List<Map<String, dynamic>> _discoveredBeacons = [];
  bool _isScanning = false;
  bool _hasPermissions = false;
  StreamSubscription<Map<String, dynamic>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _listenToScanResults();
  }

  Future<void> _checkPermissions() async {
    final hasPermissions = await _beaconsPlugin.checkPermissions();
    setState(() {
      _hasPermissions = hasPermissions;
    });
  }

  void _listenToScanResults() {
    _scanSubscription = _beaconsPlugin.scanResults.listen((device) {
      // Identify beacon type
      final beaconInfo = _identifyBeaconType(device);

      // Only add if it's a valid beacon
      if (beaconInfo['type'] != 'unknown') {
        setState(() {
          final id = device['id'] ?? device['address'] ?? '';
          final index = _discoveredBeacons.indexWhere(
            (beacon) => (beacon['id'] ?? beacon['address'] ?? '') == id,
          );

          // Add beacon type information to device
          final enrichedDevice = Map<String, dynamic>.from(device);
          enrichedDevice['beaconType'] = beaconInfo['type'];
          enrichedDevice['beaconInfo'] = beaconInfo['info'];

          if (index != -1) {
            _discoveredBeacons[index] = enrichedDevice;
          } else {
            _discoveredBeacons.add(enrichedDevice);
          }

          // Sort by RSSI (strongest signal first)
          _discoveredBeacons.sort((a, b) {
            final rssiA = a['rssi'] as int? ?? -100;
            final rssiB = b['rssi'] as int? ?? -100;
            return rssiB.compareTo(rssiA);
          });
        });
      }
    });
  }

  Map<String, dynamic> _identifyBeaconType(Map<String, dynamic> device) {
    // Check if it's Eddystone
    final serviceUuids = device['serviceUuids'] as List<dynamic>? ?? [];
    final isEddystone = serviceUuids.any(
      (uuid) => uuid.toString().toLowerCase().contains('feaa'),
    );

    if (isEddystone) {
      final serviceData = device['serviceData'] as Map<dynamic, dynamic>? ?? {};

      // Look for Eddystone service data
      for (var entry in serviceData.entries) {
        final uuid = entry.key.toString().toLowerCase();
        if (uuid.contains('feaa')) {
          final data = entry.value.toString();

          // Identify Eddystone frame type
          if (data.startsWith('00')) {
            return {'type': 'eddystone-uid', 'info': 'Eddystone-UID'};
          } else if (data.startsWith('10')) {
            return {'type': 'eddystone-url', 'info': 'Eddystone-URL'};
          } else if (data.startsWith('20')) {
            return {'type': 'eddystone-tlm', 'info': 'Eddystone-TLM'};
          } else if (data.startsWith('30')) {
            return {'type': 'eddystone-eid', 'info': 'Eddystone-EID'};
          }
          return {'type': 'eddystone', 'info': 'Eddystone'};
        }
      }
    }

    // Check if it's iBeacon
    final manufacturerData =
        device['manufacturerData'] as Map<dynamic, dynamic>? ?? {};
    for (var entry in manufacturerData.entries) {
      final manufacturerId = entry.key.toString();
      final data = entry.value.toString();

      // Apple Company ID = 76 (0x004C)
      // iBeacon has a specific format: 02 15 [UUID] [Major] [Minor] [TX Power]
      if (manufacturerId == '76' && data.length >= 40) {
        final prefix = data.substring(0, 5).replaceAll(' ', '');
        if (prefix == '0215') {
          return {'type': 'ibeacon', 'info': 'iBeacon (Apple)'};
        }
      }
    }

    // Check for AltBeacon
    if (manufacturerData.isNotEmpty) {
      for (var entry in manufacturerData.entries) {
        final data = entry.value.toString();
        // AltBeacon starts with "BE AC"
        if (data.startsWith('be ac') ||
            data.toUpperCase().startsWith('BE AC')) {
          return {'type': 'altbeacon', 'info': 'AltBeacon'};
        }
      }
    }

    // Not a known beacon
    return {'type': 'unknown', 'info': 'Not a beacon'};
  }

  Future<void> _toggleScan() async {
    // Prevent multiple clicks while processing
    if (_isScanning) {
      setState(() {
        _isScanning = false;
      });
      await _beaconsPlugin.stopScan();
    } else {
      setState(() {
        _isScanning = true;
        _discoveredBeacons.clear();
      });

      final success = await _beaconsPlugin.startScan();
      if (!success && mounted) {
        // If failed, revert state
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _refreshScan() async {
    if (!_hasPermissions) return;

    // Restart scanning
    if (_isScanning) {
      await _beaconsPlugin.stopScan();
    }

    setState(() {
      _discoveredBeacons.clear();
      _isScanning = true;
    });

    await _beaconsPlugin.startScan();

    // Small pause for visual feedback
    await Future.delayed(const Duration(milliseconds: 500));
  }

  String _getSignalStrength(int rssi) {
    if (rssi >= -60) return '📶 Excellent';
    if (rssi >= -70) return '📶 Good';
    if (rssi >= -80) return '📶 Fair';
    return '📶 Weak';
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -70) return Colors.lightGreen;
    if (rssi >= -80) return Colors.orange;
    return Colors.red;
  }

  String _getCompanyName(String companyId) {
    // Mapping of some common company IDs
    final companies = {
      '76': 'Apple, Inc.',
      '6': 'Microsoft',
      '224': 'Google',
      '89': 'Nordic Semiconductor ASA',
      '117': 'Samsung Electronics Co. Ltd.',
      '13': 'Texas Instruments Inc.',
      '15': 'Broadcom Corporation',
      '77': 'Motorola Mobility LLC',
      '186': 'Estimote, Inc.',
      '215': 'Gimbal, Inc.',
    };
    return companies[companyId] ?? '';
  }

  String _hexToAscii(String hexString) {
    // Remove spaces and convert to uppercase
    hexString = hexString.replaceAll(' ', '').toUpperCase();

    if (hexString.isEmpty || hexString.length % 2 != 0) {
      return '';
    }

    final result = StringBuffer();
    for (int i = 0; i < hexString.length; i += 2) {
      final hexByte = hexString.substring(i, i + 2);
      try {
        final byte = int.parse(hexByte, radix: 16);
        // Only show printable characters (ASCII 32-126)
        if (byte >= 32 && byte <= 126) {
          result.write(String.fromCharCode(byte));
        } else {
          result.write('.');
        }
      } catch (e) {
        result.write('?');
      }
    }
    return result.toString();
  }

  Widget _buildBeaconDetails(Map<String, dynamic> beacon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailSection('Basic Information', [
            _buildDetailRow('Name', beacon['name']?.toString() ?? 'No name'),
            _buildDetailRow('MAC Address', beacon['id']?.toString() ?? 'N/A'),
            _buildDetailRow('RSSI', '${beacon['rssi'] ?? 'N/A'} dBm'),
            _buildDetailRow('TX Power', '${beacon['txPower'] ?? 'N/A'} dBm'),
            _buildDetailRow(
              'Type',
              beacon['beaconInfo']?.toString() ?? 'Unknown',
            ),
            _buildDetailRow(
              'Connectable',
              beacon['connectable']?.toString() ?? 'N/A',
            ),
          ]),

          const SizedBox(height: 16),

          // Service UUIDs
          if ((beacon['serviceUuids'] as List<dynamic>?)?.isNotEmpty ?? false)
            _buildDetailSection(
              'Service UUIDs',
              (beacon['serviceUuids'] as List<dynamic>)
                  .map(
                    (uuid) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(
                        uuid.toString(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),

          const SizedBox(height: 16),

          // Manufacturer Data
          if ((beacon['manufacturerData'] as Map<dynamic, dynamic>?)
                  ?.isNotEmpty ??
              false)
            _buildDetailSection(
              'Manufacturer Data',
              (beacon['manufacturerData'] as Map<dynamic, dynamic>).entries.map((
                entry,
              ) {
                final companyId = entry.key.toString();
                final data = entry.value.toString();
                final asciiData = _hexToAscii(data);
                String companyName = _getCompanyName(companyId);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Company ID: $companyId (0x${int.parse(companyId).toRadixString(16).padLeft(4, '0').toUpperCase()})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (companyName.isNotEmpty)
                      Text(
                        companyName,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Hexadecimal Data
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hexadecimal:',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            data.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // ASCII Data
                    if (asciiData.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ASCII:',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              asciiData,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                );
              }).toList(),
            ),

          const SizedBox(height: 16),

          // Service Data
          if ((beacon['serviceData'] as Map<dynamic, dynamic>?)?.isNotEmpty ??
              false)
            _buildDetailSection(
              'Service Data',
              (beacon['serviceData'] as Map<dynamic, dynamic>).entries.map((
                entry,
              ) {
                final data = entry.value.toString();
                final asciiData = _hexToAscii(data);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UUID: ${entry.key}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Hexadecimal Data
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hexadecimal:',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            data.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // ASCII Data
                    if (asciiData.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ASCII:',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              asciiData,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.blue.shade800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Make sure to stop scanning when exiting
    if (_isScanning) {
      _beaconsPlugin.stopScan();
    }
    _scanSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Beacon Scanner'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Column(
          children: [
            // Control panel
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _isScanning
                                      ? Icons.bluetooth_searching
                                      : Icons.bluetooth,
                                  color: _isScanning
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isScanning ? 'Scanning...' : 'Stopped',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Beacons found: ${_discoveredBeacons.length}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _hasPermissions ? _toggleScan : null,
                        icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                        label: Text(_isScanning ? 'Stop' : 'Start'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isScanning
                              ? Colors.red.shade600
                              : Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_hasPermissions)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade800,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Location and Bluetooth permissions required',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Beacon list
            Expanded(
              child: _discoveredBeacons.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _refreshScan,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          height: MediaQuery.of(context).size.height - 200,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bluetooth_searching,
                                size: 80,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _isScanning
                                    ? 'Searching for beacons...'
                                    : 'Press "Start" to begin',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Pull down to refresh',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              if (_isScanning) ...[
                                const SizedBox(height: 20),
                                const CircularProgressIndicator(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshScan,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _discoveredBeacons.length,
                        itemBuilder: (context, index) {
                          final beacon = _discoveredBeacons[index];
                          final name = beacon['name']?.toString() ?? 'No name';
                          final id =
                              beacon['id']?.toString() ??
                              beacon['address']?.toString() ??
                              'N/A';
                          final rssi = beacon['rssi'] as int? ?? -100;
                          final beaconType =
                              beacon['beaconType']?.toString() ?? 'unknown';
                          final beaconInfo =
                              beacon['beaconInfo']?.toString() ?? '';

                          // Define icon and color based on type
                          IconData beaconIcon;
                          Color beaconColor;

                          switch (beaconType) {
                            case 'ibeacon':
                              beaconIcon = Icons.apple;
                              beaconColor = Colors.blue;
                              break;
                            case 'eddystone-uid':
                            case 'eddystone-url':
                            case 'eddystone-tlm':
                            case 'eddystone-eid':
                            case 'eddystone':
                              beaconIcon = Icons.sensors;
                              beaconColor = Colors.purple;
                              break;
                            case 'altbeacon':
                              beaconIcon = Icons.circle_notifications;
                              beaconColor = Colors.orange;
                              break;
                            default:
                              beaconIcon = Icons.bluetooth;
                              beaconColor = Colors.grey;
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 8,
                            ),
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: beaconColor.withAlpha(77),
                                width: 2,
                              ),
                            ),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.all(12),
                              childrenPadding: const EdgeInsets.all(12),
                              leading: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: beaconColor.withAlpha(77),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  beaconIcon,
                                  color: beaconColor,
                                  size: 28,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name.isEmpty ? 'Beacon' : name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: beaconColor.withAlpha(51),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: beaconColor.withAlpha(125),
                                      ),
                                    ),
                                    child: Text(
                                      beaconInfo,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: beaconColor.withAlpha(255),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Text(
                                    'MAC: ${id.toUpperCase()}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.signal_cellular_alt,
                                        size: 14,
                                        color: _getSignalColor(rssi),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'RSSI: $rssi dBm',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _getSignalStrength(rssi),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _getSignalColor(rssi),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              children: [_buildBeaconDetails(beacon)],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
