import Flutter
import UIKit
import CoreBluetooth
import CoreLocation

public class BeaconsFlutterPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private var isScanning = false
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "native_ble_scanner", binaryMessenger: registrar.messenger())
        let instance = BeaconsFlutterPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startScan":
            startScan(result: result)
        case "stopScan":
            stopScan(result: result)
        case "checkPermissions":
            checkPermissions(result: result)
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func checkPermissions(result: @escaping FlutterResult) {
        // Verificar permisos de Bluetooth
        let bluetoothAuthorized: Bool
        if #available(iOS 13.1, *) {
            bluetoothAuthorized = CBCentralManager.authorization == .allowedAlways
        } else {
            bluetoothAuthorized = CBPeripheralManager.authorizationStatus() == .authorized
        }
        
        // Verificar permisos de ubicación
        let locationStatus = CLLocationManager.authorizationStatus()
        let locationAuthorized = locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
        
        result(bluetoothAuthorized && locationAuthorized)
    }
    
    private func startScan(result: @escaping FlutterResult) {
        // Si ya está escaneando, detener primero
        if isScanning {
            centralManager?.stopScan()
            isScanning = false
        }
        
        // Inicializar LocationManager si es necesario
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.requestWhenInUseAuthorization()
        }
        
        // Inicializar CentralManager
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        
        // Verificar estado del Bluetooth
        guard let central = centralManager else {
            result(FlutterError(code: "NO_CENTRAL", message: "Central Manager not available", details: nil))
            return
        }
        
        if central.state != .poweredOn {
            result(FlutterError(code: "BLUETOOTH_OFF", message: "Bluetooth is not powered on", details: nil))
            return
        }
        
        // Iniciar escaneo
        discoveredPeripherals.removeAll()
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        isScanning = true
        
        channel?.invokeMethod("onScanStarted", arguments: nil)
        result(true)
    }
    
    private func stopScan(result: @escaping FlutterResult) {
        guard isScanning else {
            result(false)
            return
        }
        
        centralManager?.stopScan()
        isScanning = false
        
        channel?.invokeMethod("onScanStopped", arguments: nil)
        result(true)
    }
}

// MARK: - CBCentralManagerDelegate
extension BeaconsFlutterPlugin: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isScanning {
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
        }
    }
    
    public func centralManager(_ central: CBCentralManager, 
                              didDiscover peripheral: CBPeripheral, 
                              advertisementData: [String: Any], 
                              rssi RSSI: NSNumber) {
        
        // Filtrar dispositivos con RSSI muy bajo
        if RSSI.intValue == 127 || RSSI.intValue < -100 {
            return
        }
        
        var deviceData: [String: Any] = [:]
        
        // Información básica
        deviceData["id"] = peripheral.identifier.uuidString
        deviceData["name"] = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        deviceData["rssi"] = RSSI.intValue
        
        // TX Power
        if let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            deviceData["txPower"] = txPower.intValue
        } else {
            deviceData["txPower"] = 0
        }
        
        // Connectable
        if let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {
            deviceData["connectable"] = isConnectable.boolValue
        } else {
            deviceData["connectable"] = true
        }
        
        // Service UUIDs
        var serviceUuids: [String] = []
        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            serviceUuids = services.map { $0.uuidString }
        }
        deviceData["serviceUuids"] = serviceUuids
        
        // Manufacturer Data
        var manufacturerData: [String: String] = [:]
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if data.count >= 2 {
                // Los primeros 2 bytes son el Company ID (little-endian)
                let companyId = UInt16(data[0]) | (UInt16(data[1]) << 8)
                let payload = data.subdata(in: 2..<data.count)
                manufacturerData[String(companyId)] = payload.map { String(format: "%02x", $0) }.joined(separator: " ")
            }
        }
        deviceData["manufacturerData"] = manufacturerData
        
        // Service Data
        var serviceData: [String: String] = [:]
        if let serviceDataDict = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in serviceDataDict {
                serviceData[uuid.uuidString] = data.map { String(format: "%02x", $0) }.joined(separator: " ")
            }
        }
        deviceData["serviceData"] = serviceData
        
        // Detectar si es Eddystone
        let isEddystone = serviceUuids.contains { $0.lowercased().contains("feaa") }
        deviceData["isEddystone"] = isEddystone
        
        // Enviar al canal de Flutter
        channel?.invokeMethod("onDeviceFound", arguments: deviceData)
    }
}
