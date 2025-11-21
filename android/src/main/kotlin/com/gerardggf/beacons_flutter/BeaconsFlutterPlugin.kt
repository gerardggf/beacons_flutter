package com.gerardggf.beacons_flutter

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class BeaconsFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, 
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var isScanning = false
    private val handler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val CHANNEL = "native_ble_scanner"
        private const val PERMISSION_REQUEST_CODE = 12345
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stopScan(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> startScan(result)
            "stopScan" -> stopScan(result)
            "checkPermissions" -> checkPermissions(result)
            "requestPermissions" -> requestPermissions(result)
            else -> result.notImplemented()
        }
    }

    private fun getRequiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }
    }

    private fun checkPermissions(result: MethodChannel.Result) {
        val permissions = getRequiredPermissions()
        val allGranted = permissions.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
        result.success(allGranted)
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        val permissions = getRequiredPermissions()
        val missingPermissions = permissions.filter {
            ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()

        if (missingPermissions.isEmpty()) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity!!, missingPermissions, PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(allGranted)
            pendingPermissionResult = null
            return true
        }
        return false
    }

    // ActivityAware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    @SuppressLint("MissingPermission")
    private fun startScan(result: MethodChannel.Result?) {
        // If already scanning, stop first
        if (isScanning) {
            try {
                bluetoothLeScanner?.stopScan(scanCallback)
                isScanning = false
            } catch (e: Exception) {
                // Ignore errors when stopping
            }
        }

        if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
            result?.error("BLUETOOTH_OFF", "Bluetooth is not enabled", null)
            return
        }

        if (bluetoothLeScanner == null) {
            result?.error("NO_SCANNER", "BluetoothLeScanner is not available", null)
            return
        }

        try {
            val scanSettings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                .setReportDelay(0)
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        setLegacy(true)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
                    }
                }
                .build()

            val scanFilters = emptyList<ScanFilter>()

            bluetoothLeScanner?.startScan(scanFilters, scanSettings, scanCallback)
            isScanning = true
            
            channel.invokeMethod("onScanStarted", null)
            result?.success(true)
        } catch (e: Exception) {
            result?.error("SCAN_ERROR", "Failed to start scan: ${e.message}", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopScan(result: MethodChannel.Result?) {
        if (!isScanning) {
            result?.success(false)
            return
        }

        try {
            bluetoothLeScanner?.stopScan(scanCallback)
            isScanning = false
            channel.invokeMethod("onScanStopped", null)
            result?.success(true)
        } catch (e: Exception) {
            result?.error("STOP_ERROR", "Failed to stop scan: ${e.message}", null)
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            handler.post {
                val device = result.device
                val scanRecord = result.scanRecord
                
                val deviceData = hashMapOf<String, Any?>(
                    "id" to device.address,
                    "name" to (scanRecord?.deviceName ?: device.name ?: ""),
                    "rssi" to result.rssi,
                    "txPower" to (scanRecord?.txPowerLevel ?: 0),
                    "connectable" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.isConnectable
                    } else true
                )

                val serviceUuids = scanRecord?.serviceUuids?.map { it.toString() } ?: emptyList()
                deviceData["serviceUuids"] = serviceUuids

                val manufacturerData = scanRecord?.manufacturerSpecificData
                val manufacturerMap = mutableMapOf<String, String>()
                if (manufacturerData != null) {
                    for (i in 0 until manufacturerData.size()) {
                        val key = manufacturerData.keyAt(i)
                        val value = manufacturerData.valueAt(i)
                        manufacturerMap[key.toString()] = bytesToHex(value)
                    }
                }
                deviceData["manufacturerData"] = manufacturerMap

                val serviceData = scanRecord?.serviceData
                val serviceDataMap = mutableMapOf<String, String>()
                serviceData?.forEach { (uuid, data) ->
                    serviceDataMap[uuid.toString()] = bytesToHex(data)
                }
                deviceData["serviceData"] = serviceDataMap

                val isEddystone = serviceUuids.any { it.contains("feaa", ignoreCase = true) }
                deviceData["isEddystone"] = isEddystone

                channel.invokeMethod("onDeviceFound", deviceData)
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
        }

        override fun onScanFailed(errorCode: Int) {
            handler.post {
                val errorMessage = when (errorCode) {
                    SCAN_FAILED_ALREADY_STARTED -> "Scan already started"
                    SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "App registration failed"
                    SCAN_FAILED_FEATURE_UNSUPPORTED -> "Feature not supported"
                    SCAN_FAILED_INTERNAL_ERROR -> "Internal error"
                    else -> "Unknown error: $errorCode"
                }
                channel.invokeMethod("onScanError", hashMapOf("error" to errorMessage))
                isScanning = false
            }
        }
    }

    private fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString(" ") { "%02x".format(it) }
    }
}