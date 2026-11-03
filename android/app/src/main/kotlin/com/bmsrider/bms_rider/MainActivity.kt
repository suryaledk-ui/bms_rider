package com.bmsrider.bms_rider

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "bmsrider/permissions"
    private val legacyScanChannelName = "bmsrider/legacy_scan"
    private val locationServicesChannelName = "bmsrider/location_services"
    private var pendingResult: MethodChannel.Result? = null

    // ---- Legacy BLE scan (BluetoothAdapter.startLeScan) ----
    // BAT-BMS/FastBLE uses this legacy API. On cheap Android 12 stacks
    // (MediaTek/LAVA) the new BluetoothLeScanner.startScan() silently returns
    // nothing while the legacy API works.
    private var legacyScanHandler: Handler? = null
    private var legacyScanStopRunnable: Runnable? = null
    private val legacyScanResults = HashMap<String, MutableMap<String, Any>>()

    private val legacyScanCallback = object : BluetoothAdapter.LeScanCallback {
        override fun onLeScan(device: BluetoothDevice?, rssi: Int, scanRecord: ByteArray?) {
            device ?: return
            val entry = legacyScanResults.getOrPut(device.address) {
                mutableMapOf(
                    "id" to device.address,
                    "name" to (device.name ?: ""),
                    "rssi" to rssi
                )
            }
            if ((entry["name"] as String).isEmpty()) {
                entry["name"] = device.name ?: ""
            }
            entry["rssi"] = rssi
        }
    }

    private fun startLegacyScan(timeoutMs: Long, result: MethodChannel.Result) {
        // Cancel any previous pending scan first.
        legacyScanHandler?.removeCallbacksAndMessages(null)
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: run {
                result.success(listOf<Map<String, Any>>())
                return
            }
            legacyScanResults.clear()
            val ok = adapter.startLeScan(legacyScanCallback)
            if (!ok) {
                result.success(listOf<Map<String, Any>>())
                return
            }
            legacyScanHandler = Handler(Looper.getMainLooper())
            legacyScanStopRunnable = Runnable {
                try {
                    adapter.stopLeScan(legacyScanCallback)
                } catch (_: Exception) {
                }
                result.success(legacyScanResults.values.toList())
            }
            legacyScanHandler?.postDelayed(legacyScanStopRunnable!!, timeoutMs)
        } catch (e: Exception) {
            result.success(listOf<Map<String, Any>>())
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestBle" -> {
                        val perms = mutableListOf<String>()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            perms.add(Manifest.permission.BLUETOOTH_SCAN)
                            perms.add(Manifest.permission.BLUETOOTH_CONNECT)
                        } else {
                            perms.add(Manifest.permission.ACCESS_FINE_LOCATION)
                        }
                        // Fine location is still required by many OEM stacks
                        // (LAVA/MediaTek/Samsung) for full beacon visibility.
                        perms.add(Manifest.permission.ACCESS_FINE_LOCATION)
                        requestImpl(perms.distinct(), result)
                    }
                    "requestLocation" -> {
                        requestImpl(listOf(Manifest.permission.ACCESS_FINE_LOCATION), result)
                    }
                    "openSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationServicesChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> {
                        result.success(isLocationServicesEnabled())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, legacyScanChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scan" -> {
                        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: 6000L)
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                            checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED ||
                            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        ) {
                            startLegacyScan(timeoutMs, result)
                        } else {
                            result.success(listOf<Map<String, Any>>())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isLocationServicesEnabled(): Boolean {
        val lm = applicationContext.getSystemService(android.content.Context.LOCATION_SERVICE) as? LocationManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            android.provider.Settings.Secure.getInt(
                contentResolver,
                android.provider.Settings.Secure.LOCATION_MODE,
                android.provider.Settings.Secure.LOCATION_MODE_OFF,
            ) != android.provider.Settings.Secure.LOCATION_MODE_OFF
        }
    }

    private fun requestImpl(perms: List<String>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(mapOf("granted" to true))
            return
        }
        val missing = perms.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(mapOf("granted" to true))
        } else {
            pendingResult = result
            requestPermissions(missing.toTypedArray(), 1001)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val allGranted =
                grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingResult?.success(mapOf("granted" to allGranted))
            pendingResult = null
        }
    }
}
