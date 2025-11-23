import Flutter
import UIKit
import CoreBluetooth
import CoreLocation

public class BeaconsFlutterPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private var isScanning = false
    private var pendingResult: FlutterResult?
    private var pendingScanResult: FlutterResult?
    private var discoveredDevices: [String: [String: Any]] = [:]
    private var beaconRegions: [CLBeaconRegion] = []
    private var iBeaconUUIDs: [String] = []
    
    private static let CHANNEL = "native_ble_scanner"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: registrar.messenger())
        let instance = BeaconsFlutterPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public override init() {
        super.init()
        // No inicializar CBCentralManager aquí para evitar solicitar permisos demasiado pronto
        locationManager = CLLocationManager()
        locationManager?.delegate = self
    }
    
    private func initializeCentralManagerIfNeeded() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startScan":
            // Extraer los UUIDs de iBeacons si se proporcionan
            if let args = call.arguments as? [String: Any],
               let uuids = args["iBeaconUUIDs"] as? [String] {
                iBeaconUUIDs = uuids
            } else {
                iBeaconUUIDs = []
            }
            startScan(result: result)
        case "stopScan":
            stopScan(result: result)
        case "checkPermissions":
            checkPermissions(result: result)
        case "requestPermissions":
            requestPermissions(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func checkPermissions(result: @escaping FlutterResult) {
        initializeCentralManagerIfNeeded()
        
        let bluetoothAuthorized = checkBluetoothPermission()
        let locationAuthorized = checkLocationPermission()
        
        let allGranted = bluetoothAuthorized && locationAuthorized
        result(allGranted)
    }
    
    private func checkBluetoothPermission() -> Bool {
        guard let centralManager = centralManager else {
            return false
        }
        
        // En iOS 13.1+, verificar autorización de Bluetooth
        if #available(iOS 13.1, *) {
            let authorization = CBCentralManager.authorization
            
            // Verificar si está autorizado o si el estado es desconocido (aún no se ha solicitado)
            // En iOS, el permiso de Bluetooth se solicita automáticamente al escanear
            switch authorization {
            case .allowedAlways:
                return true
            case .denied, .restricted:
                return false
            case .notDetermined:
                // Si no está determinado, verificar el estado del manager
                return centralManager.state == .poweredOn || centralManager.state == .unknown
            @unknown default:
                return centralManager.state == .poweredOn
            }
        } else {
            // En versiones anteriores, verificar solo el estado
            return centralManager.state == .poweredOn || centralManager.state == .unknown
        }
    }
    
    private func checkLocationPermission() -> Bool {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager?.authorizationStatus ?? .notDetermined
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }
    
    private func requestPermissions(result: @escaping FlutterResult) {
        initializeCentralManagerIfNeeded()
        
        pendingResult = result
        
        // Solicitar permisos de ubicación primero
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager?.authorizationStatus ?? .notDetermined
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        
        if status == .notDetermined {
            locationManager?.requestWhenInUseAuthorization()
            // El resultado se enviará en el delegate de locationManager
        } else {
            // Si los permisos de ubicación ya están concedidos o denegados
            let allGranted = checkBluetoothPermission() && checkLocationPermission()
            result(allGranted)
            pendingResult = nil
        }
    }
    
    private func startScan(result: @escaping FlutterResult) {
        initializeCentralManagerIfNeeded()
        
        // Si ya está escaneando, detener primero
        if isScanning {
            stopAllScanning()
        }
        
        guard let centralManager = centralManager else {
            result(FlutterError(code: "NO_MANAGER", message: "CBCentralManager is not available", details: nil))
            return
        }
        
        // Si el Bluetooth no está encendido aún, guardar el resultado para cuando esté listo
        if centralManager.state != .poweredOn {
            if centralManager.state == .poweredOff {
                result(FlutterError(code: "BLUETOOTH_OFF", message: "Bluetooth is powered off", details: nil))
                return
            }
            // Si está en otro estado (unauthorized, unsupported, etc)
            if centralManager.state == .unauthorized {
                result(FlutterError(code: "BLUETOOTH_UNAUTHORIZED", message: "Bluetooth is unauthorized", details: nil))
                return
            }
            if centralManager.state == .unsupported {
                result(FlutterError(code: "BLUETOOTH_UNSUPPORTED", message: "Bluetooth is not supported", details: nil))
                return
            }
            // Para estados unknown o resetting, esperar un momento
            pendingScanResult = result
            // Esperar hasta 2 segundos para que el manager esté listo
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if let pendingResult = self.pendingScanResult {
                    self.pendingScanResult = nil
                    if self.centralManager?.state == .poweredOn {
                        self.startScan(result: pendingResult)
                    } else {
                        pendingResult(FlutterError(code: "BLUETOOTH_NOT_READY", message: "Bluetooth is not ready", details: nil))
                    }
                }
            }
            return
        }
        
        // Limpiar dispositivos descubiertos
        discoveredDevices.removeAll()
        
        // 1. Escaneo BLE para Eddystone, AltBeacon y otros beacons
        // Escaneamos específicamente por Eddystone (FEAA) y sin filtro para el resto
        centralManager.scanForPeripherals(
            withServices: nil, // Escanear todos los servicios
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
        )
        
        // 2. Ranging de iBeacons si se especificaron UUIDs
        if !iBeaconUUIDs.isEmpty {
            startIBeaconRanging()
        }
        
        isScanning = true
        channel?.invokeMethod("onScanStarted", arguments: nil)
        result(true)
    }
    
    private func startIBeaconRanging() {
        guard let locationManager = locationManager else { return }
        
        // Limpiar regiones anteriores
        for region in beaconRegions {
            locationManager.stopRangingBeacons(in: region)
        }
        beaconRegions.removeAll()
        
        // Crear regiones para cada UUID de iBeacon
        for uuidString in iBeaconUUIDs {
            guard let uuid = UUID(uuidString: uuidString) else {
                continue
            }
            
            let region = CLBeaconRegion(
                uuid: uuid,
                identifier: "iBeacon-\(uuidString)"
            )
            
            beaconRegions.append(region)
            locationManager.startRangingBeacons(in: region)
        }
    }
    
    private func stopAllScanning() {
        // Detener escaneo BLE
        centralManager?.stopScan()
        
        // Detener ranging de iBeacons
        guard let locationManager = locationManager else { return }
        for region in beaconRegions {
            locationManager.stopRangingBeacons(in: region)
        }
        
        isScanning = false
    }
    
    private func stopScan(result: @escaping FlutterResult) {
        if !isScanning {
            result(false)
            return
        }
        
        stopAllScanning()
        channel?.invokeMethod("onScanStopped", arguments: nil)
        result(true)
    }
    
    private func bytesToHex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
    
    private func parseAdvertisementData(_ advertisementData: [String: Any], peripheral: CBPeripheral, rssi: NSNumber) -> [String: Any] {
        var deviceData: [String: Any] = [:]
        
        // ID y nombre
        deviceData["id"] = peripheral.identifier.uuidString
        deviceData["name"] = peripheral.name ?? ""
        deviceData["rssi"] = rssi.intValue
        
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
            serviceUuids = services.map { $0.uuidString.lowercased() }
        }
        deviceData["serviceUuids"] = serviceUuids
        
        // Manufacturer Data
        var manufacturerDataMap: [String: String] = [:]
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if manufacturerData.count >= 2 {
                // Los primeros 2 bytes son el company identifier (little-endian)
                let companyId = UInt16(manufacturerData[0]) | (UInt16(manufacturerData[1]) << 8)
                let payloadData = manufacturerData.subdata(in: 2..<manufacturerData.count)
                manufacturerDataMap[String(companyId)] = bytesToHex(payloadData)
            }
        }
        deviceData["manufacturerData"] = manufacturerDataMap
        
        // Service Data
        var serviceDataMap: [String: String] = [:]
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in serviceData {
                serviceDataMap[uuid.uuidString.lowercased()] = bytesToHex(data)
            }
        }
        deviceData["serviceData"] = serviceDataMap
        
        // Detectar si es Eddystone (UUID de servicio FEAA)
        let isEddystone = serviceUuids.contains { $0.contains("feaa") }
        deviceData["isEddystone"] = isEddystone
        
        return deviceData
    }
}

extension BeaconsFlutterPlugin: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Si hay un escaneo pendiente y ahora el Bluetooth está encendido, iniciar escaneo
        if let pendingScan = pendingScanResult, central.state == .poweredOn {
            pendingScanResult = nil
            startScan(result: pendingScan)
        }
        
        switch central.state {
        case .poweredOff:
            if isScanning {
                isScanning = false
                channel?.invokeMethod("onScanStopped", arguments: nil)
            }
        case .poweredOn:
            break
        case .unauthorized:
            break
        case .unsupported:
            break
        default:
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Filtrar dispositivos con RSSI muy bajo (fuera de rango)
        if RSSI.intValue == 127 || RSSI.intValue == 0 {
            return
        }
        
        let deviceData = parseAdvertisementData(advertisementData, peripheral: peripheral, rssi: RSSI)
        
        // Enviar al canal Flutter
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onDeviceFound", arguments: deviceData)
        }
    }
}

extension BeaconsFlutterPlugin: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if let result = pendingResult {
            let allGranted = checkBluetoothPermission() && checkLocationPermission()
            result(allGranted)
            pendingResult = nil
        }
    }
    
    @available(iOS 14.0, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if let result = pendingResult {
            let allGranted = checkBluetoothPermission() && checkLocationPermission()
            result(allGranted)
            pendingResult = nil
        }
    }
    
    // Ranging de iBeacons (iOS 13+)
    public func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        for beacon in beacons {
            // Convertir CLBeacon a formato compatible con Flutter
            let deviceData = parseIBeacon(beacon)
            
            // Enviar al canal Flutter
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod("onDeviceFound", arguments: deviceData)
            }
        }
    }
    
    // Ranging de iBeacons (legacy iOS 12 y anteriores)
    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        for beacon in beacons {
            let deviceData = parseIBeacon(beacon)
            
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod("onDeviceFound", arguments: deviceData)
            }
        }
    }
    
    private func parseIBeacon(_ beacon: CLBeacon) -> [String: Any] {
        var deviceData: [String: Any] = [:]
        
        // ID único basado en UUID + Major + Minor
        let beaconId = "\(beacon.uuid.uuidString)-\(beacon.major)-\(beacon.minor)"
        deviceData["id"] = beaconId
        deviceData["name"] = "iBeacon"
        
        // RSSI y accuracy
        deviceData["rssi"] = beacon.rssi
        deviceData["txPower"] = 0 // No disponible directamente en CLBeacon
        deviceData["connectable"] = false
        
        // Información específica de iBeacon
        deviceData["serviceUuids"] = []
        deviceData["serviceData"] = [:]
        
        // Manufacturer Data con formato iBeacon
        // Company ID 76 (Apple) + formato iBeacon
        let iBeaconData = formatIBeaconAsManufacturerData(
            uuid: beacon.uuid,
            major: beacon.major.uint16Value,
            minor: beacon.minor.uint16Value
        )
        deviceData["manufacturerData"] = ["76": iBeaconData]
        deviceData["isEddystone"] = false
        
        // Datos adicionales de proximidad
        deviceData["accuracy"] = beacon.accuracy
        deviceData["proximity"] = proximityToString(beacon.proximity)
        
        return deviceData
    }
    
    private func formatIBeaconAsManufacturerData(uuid: UUID, major: UInt16, minor: UInt16) -> String {
        // Formato iBeacon: 02 15 [UUID 16 bytes] [Major 2 bytes] [Minor 2 bytes] [TX Power 1 byte]
        var dataString = "02 15 "
        
        // UUID (16 bytes)
        let uuidBytes = uuid.uuid
        let uuidString = withUnsafeBytes(of: uuidBytes) { bytes in
            bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        }
        dataString += uuidString + " "
        
        // Major (2 bytes, big-endian)
        dataString += String(format: "%02x %02x ", UInt8(major >> 8), UInt8(major & 0xFF))
        
        // Minor (2 bytes, big-endian)
        dataString += String(format: "%02x %02x ", UInt8(minor >> 8), UInt8(minor & 0xFF))
        
        // TX Power (1 byte, placeholder)
        dataString += "c5"
        
        return dataString
    }
    
    private func proximityToString(_ proximity: CLProximity) -> String {
        switch proximity {
        case .immediate:
            return "immediate"
        case .near:
            return "near"
        case .far:
            return "far"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
}
