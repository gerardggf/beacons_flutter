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
            centralManager?.stopScan()
            isScanning = false
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
        
        // Iniciar escaneo sin filtros para obtener todos los dispositivos
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
        )
        
        isScanning = true
        channel?.invokeMethod("onScanStarted", arguments: nil)
        result(true)
    }
    
    private func stopScan(result: @escaping FlutterResult) {
        if !isScanning {
            result(false)
            return
        }
        
        centralManager?.stopScan()
        isScanning = false
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
}
