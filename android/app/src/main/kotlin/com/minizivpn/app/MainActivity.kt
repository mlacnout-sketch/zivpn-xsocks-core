package com.minizivpn.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.util.Log
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.os.Build

import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter

import android.net.TrafficStats
import java.util.Timer
import java.util.TimerTask
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat

/**
 * ZIVPN Turbo Main Activity
 * Optimized for high-performance tunneling and aggressive cleanup.
 */
class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.minizivpn.app/core"
    private val LOG_CHANNEL = "com.minizivpn.app/logs"
    private val STATS_CHANNEL = "com.minizivpn.app/stats"
    private val ACTION_LOG = "com.minizivpn.app.LOG"
    private val REQUEST_VPN_CODE = 1
    private val REQUEST_NOTIFICATION_PERMISSION_CODE = 2
    
    private var logSink: EventChannel.EventSink? = null
    private var statsSink: EventChannel.EventSink? = null
    private var statsTimer: Timer? = null
    private var initialIntentData: String? = null // Store file URI
    
    private val uiHandler = Handler(Looper.getMainLooper())

    private val logReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val log = intent?.getStringExtra("message")
            if (log != null) {
                sendToLog(log)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent) // Check intent on launch
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(logReceiver, IntentFilter(ACTION_LOG), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(logReceiver, IntentFilter(ACTION_LOG))
        }
        
        checkAndRequestNotificationPermission()
    }

    override fun onBackPressed() {
        // Move app to background instead of closing
        moveTaskToBack(true)
    }

    private fun checkAndRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION_CODE)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent) // Check intent on new intent (already running)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val data = intent.data
            if (data != null) {
                // Copy content stream to temp file to be accessible by Flutter File object
                try {
                    val inputStream = contentResolver.openInputStream(data)
                    val tempFile = java.io.File(cacheDir, "import_backup.zip")
                    if (tempFile.exists()) tempFile.delete()
                    
                    val outputStream = java.io.FileOutputStream(tempFile)
                    inputStream?.copyTo(outputStream)
                    
                    inputStream?.close()
                    outputStream.close()
                    
                    initialIntentData = tempFile.absolutePath
                    Log.d("ZIVPN-Import", "File copied to: $initialIntentData")
                } catch (e: Exception) {
                    Log.e("ZIVPN-Import", "Failed to copy content: ${e.message}")
                    initialIntentData = null
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LOG_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    logSink = events
                    sendToLog("Logging system initialized.")
                }
                override fun onCancel(arguments: Any?) {
                    logSink = null
                }
            }
        )
        
        // Traffic Stats Handler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    statsSink = events
                    startStatsTimer()
                }
                override fun onCancel(arguments: Any?) {
                    statsSink = null
                    stopStatsTimer()
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                result.success(initialIntentData)
                initialIntentData = null // Clear after reading
            } else if (call.method == "startCore") {
                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                
                // Strings
                prefs.putString("flutter.server_ip", call.argument<String>("ip") ?: "")
                prefs.putString("flutter.server_range", call.argument<String>("port_range") ?: "6000-19999")
                prefs.putString("flutter.server_pass", call.argument<String>("pass") ?: "")
                prefs.putString("flutter.server_obfs", call.argument<String>("obfs") ?: "hu``hqb`c")
                prefs.putString("flutter.udp_mode", call.argument<String>("udp_mode") ?: "udp")
                prefs.putString("flutter.udpgw_port", call.argument<String>("udpgw_port") ?: "7300")
                prefs.putString("flutter.udpgw_max_connections", call.argument<String>("udpgw_max_connections") ?: "512")
                prefs.putString("flutter.udpgw_buffer_size", call.argument<String>("udpgw_buffer_size") ?: "32")
                prefs.putString("flutter.tcp_snd_buf", call.argument<String>("tcp_snd_buf") ?: "65535")
                prefs.putString("flutter.tcp_wnd", call.argument<String>("tcp_wnd") ?: "65535")
                prefs.putString("flutter.socks_buf", call.argument<String>("socks_buf") ?: "65536")
                prefs.putString("flutter.log_level", call.argument<String>("log_level") ?: "info")
                prefs.putString("flutter.ping_target", call.argument<String>("ping_target") ?: "http://www.gstatic.com/generate_204")
                prefs.putString("flutter.apps_list", call.argument<String>("apps_list") ?: "")
                prefs.putString("flutter.upstream_dns", call.argument<String>("upstream_dns") ?: "208.67.222.222")
                prefs.putString("flutter.native_perf_profile", call.argument<String>("native_perf_profile") ?: "balanced")
                prefs.putString("flutter.pdnsd_min_ttl", call.argument<String>("pdnsd_min_ttl") ?: "15m")
                prefs.putString("flutter.pdnsd_max_ttl", call.argument<String>("pdnsd_max_ttl") ?: "1w")
                prefs.putString("flutter.pdnsd_query_method", call.argument<String>("pdnsd_query_method") ?: "tcp_only")

                prefs.putString("flutter.libuz_up", call.argument<String>("up") ?: "100")
                prefs.putString("flutter.libuz_down_mbps", call.argument<String>("down_mbps") ?: "100")
                prefs.putString("flutter.libuz_rcveconn", call.argument<String>("rcveconn") ?: "131072")
                prefs.putString("flutter.libuz_recvwindow", call.argument<String>("recvwindow") ?: "327680")

                // Booleans
                prefs.putBoolean("flutter.enable_udpgw", call.argument<Boolean>("enable_udpgw") ?: true)
                prefs.putBoolean("flutter.filter_apps", call.argument<Boolean>("filter_apps") ?: false)
                prefs.putBoolean("flutter.bypass_mode", call.argument<Boolean>("bypass_mode") ?: false)
                prefs.putBoolean("flutter.cpu_wakelock", call.argument<Boolean>("cpu_wakelock") ?: false)
                prefs.putBoolean("flutter.udpgw_transparent_dns", call.argument<Boolean>("udpgw_transparent_dns") ?: false)

                // Integers
                prefs.putInt("flutter.mtu", call.argument<Int>("mtu") ?: 1500)
                prefs.putInt("flutter.ping_interval", call.argument<Int>("ping_interval") ?: 3)
                prefs.putInt("flutter.core_count", call.argument<Int>("core_count") ?: 4)
                prefs.putInt("flutter.pdnsd_port", call.argument<Int>("pdnsd_port") ?: 8091)
                prefs.putInt("flutter.pdnsd_cache_entries", call.argument<Int>("pdnsd_cache_entries") ?: 2048)
                prefs.putInt("flutter.pdnsd_timeout_sec", call.argument<Int>("pdnsd_timeout_sec") ?: 10)
                prefs.putInt("flutter.pdnsd_verbosity", call.argument<Int>("pdnsd_verbosity") ?: 2)
                
                prefs.apply()

                sendToLog("Config saved. Ready to start VPN.")
                result.success("READY")
            } else if (call.method == "logMessage") {
                val msg = call.argument<String>("message") ?: ""
                sendToLog(msg)
                result.success("Logged")
            } else if (call.method == "stopCore") {
                stopVpn()
                result.success("Stopped")
            } else if (call.method == "startVpn") {
                startVpn(result)
            } else if (call.method == "getInstalledApps") {
                Thread {
                    val apps = mutableListOf<Map<String, String>>()
                    val pm = packageManager
                    val packages = pm.getInstalledPackages(0)
                    for (pkg in packages) {
                        // Skip if applicationInfo is null
                        val appInfo = pkg.applicationInfo ?: continue
                        val label = pm.getApplicationLabel(appInfo).toString()
                        val packageName = pkg.packageName
                        
                        val appMap = mapOf(
                            "name" to label,
                            "package" to packageName
                        )
                        apps.add(appMap)
                    }
                    // Sort by name
                    apps.sortBy { it["name"]?.lowercase() }
                    
                    uiHandler.post {
                        result.success(apps)
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startStatsTimer() {
        stopStatsTimer()
        statsTimer = Timer()
        val uid = android.os.Process.myUid()
        var lastRx = TrafficStats.getUidRxBytes(uid)
        var lastTx = TrafficStats.getUidTxBytes(uid)
        
        statsTimer?.schedule(object : TimerTask() {
            override fun run() {
                val currentRx = TrafficStats.getUidRxBytes(uid)
                val currentTx = TrafficStats.getUidTxBytes(uid)
                
                val rxSpeed = currentRx - lastRx
                val txSpeed = currentTx - lastTx
                
                lastRx = currentRx
                lastTx = currentTx
                
                // Only send if positive (handle reboot/overflow)
                if (rxSpeed >= 0 && txSpeed >= 0) {
                    uiHandler.post {
                        statsSink?.success("$rxSpeed|$txSpeed")
                    }
                }
            }
        }, 1000, 1000)
    }

    private fun stopStatsTimer() {
        statsTimer?.cancel()
        statsTimer = null
    }

    private fun sendToLog(msg: String) {
        uiHandler.post {
            logSink?.success(msg)
        }
        Log.d("ZIVPN-Core", msg)
    }

    private fun startVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, REQUEST_VPN_CODE)
            result.success("REQUEST_PERMISSION")
            sendToLog("Requesting VPN permission...")
        } else {
            val serviceIntent = Intent(this, ZivpnService::class.java)
            serviceIntent.action = ZivpnService.ACTION_CONNECT
            ContextCompat.startForegroundService(this, serviceIntent)
            result.success("STARTED")
            sendToLog("VPN Service started.")
        }
    }

    private fun stopVpn() {
        val serviceIntent = Intent(this, ZivpnService::class.java)
        serviceIntent.action = ZivpnService.ACTION_DISCONNECT
        startService(serviceIntent)
        sendToLog("VPN Service stopped.")
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_CODE) {
            if (resultCode == RESULT_OK) {
                val serviceIntent = Intent(this, ZivpnService::class.java)
                serviceIntent.action = ZivpnService.ACTION_CONNECT
                ContextCompat.startForegroundService(this, serviceIntent)
                sendToLog("VPN permission granted. Starting service.")
            } else {
                sendToLog("VPN permission denied.")
            }
        }
    }

    private fun stopEngine() {
        val intent = Intent(this, ZivpnService::class.java)
        intent.action = ZivpnService.ACTION_DISCONNECT
        ContextCompat.startForegroundService(this, intent)

        // Brute force cleanup for ALL instances of the cores in background
        Thread {
            try {
                val cleanupCmd = arrayOf("sh", "-c", "pkill -9 libuz; pkill -9 libload; pkill -9 libuz.so; pkill -9 libload.so; pkill -9 libtun2socks.so")
                Runtime.getRuntime().exec(cleanupCmd).waitFor()
            } catch (e: Exception) {}
        }.start()
        
        sendToLog("Aggressive cleanup triggered in background.")
    }
    
    override fun onDestroy() {
        stopStatsTimer() // Clean up timer
        try {
            unregisterReceiver(logReceiver)
        } catch (e: Exception) {}
        super.onDestroy()
    }
}
