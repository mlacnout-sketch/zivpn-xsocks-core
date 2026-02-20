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

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.app.Notification
import android.app.NotificationManager
import android.app.NotificationChannel

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
    private lateinit var proxyUsageManager: ProxyUsageManager
    private var lastNetworkStatsTotal: Long = 0L
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
        proxyUsageManager = ProxyUsageManager(this)
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

        registerAutoPilotChannel(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                result.success(initialIntentData)
                initialIntentData = null // Clear after reading
            } else if (call.method == "getSmartNetworkConfig") {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.READ_PHONE_STATE), 101)
                    result.error("PERMISSION_DENIED", "Permission requested", null)
                } else {
                    val probe = NetworkProbe(this)
                    val config = probe.getSmartConfig()
                    result.success(config)
                }
            } else if (call.method == "checkUpdateNative") {
                val urlStr = call.argument<String>("url")
                Thread {
                    try {
                        val url = java.net.URL(urlStr)
                        // Use SOCKS5 Proxy to loop back into our own VPN core
                        // This works even if the app is excluded from the VPN.
                        val proxy = java.net.Proxy(java.net.Proxy.Type.SOCKS, java.net.InetSocketAddress("127.0.0.1", 7777))
                        
                        val conn = url.openConnection(proxy) as java.net.HttpURLConnection
                        conn.connectTimeout = 15000
                        conn.readTimeout = 15000
                        conn.setRequestProperty("User-Agent", "MiniZIVPN-Updater")
                        
                        val responseCode = conn.responseCode
                        val stream = if (responseCode >= 400) conn.errorStream else conn.inputStream
                        val reader = java.io.BufferedReader(java.io.InputStreamReader(stream))
                        val sb = StringBuilder()
                        var line: String?
                        while (reader.readLine().also { line = it } != null) sb.append(line)
                        reader.close()
                        
                        uiHandler.post { result.success(sb.toString()) }
                    } catch (e: Exception) {
                        Log.e("ZIVPN-Updater", "SOCKS5 Check failed: ${e.message}")
                        // Fallback to direct if SOCKS5 fails (e.g. VPN not yet ready)
                        Thread {
                            try {
                                val conn = java.net.URL(urlStr).openConnection() as java.net.HttpURLConnection
                                conn.connectTimeout = 5000
                                val reader = java.io.BufferedReader(java.io.InputStreamReader(conn.inputStream))
                                val sb = StringBuilder()
                                var line: String?
                                while (reader.readLine().also { line = it } != null) sb.append(line)
                                reader.close()
                                uiHandler.post { result.success(sb.toString()) }
                            } catch (e2: Exception) {
                                uiHandler.post { result.error("ERR", e2.message, null) }
                            }
                        }.start()
                    }
                }.start()
            } else if (call.method == "downloadUpdateNative") {
                val urlStr = call.argument<String>("url")
                val destPath = call.argument<String>("path")
                Thread {
                    try {
                        val url = java.net.URL(urlStr)
                        val proxy = java.net.Proxy(java.net.Proxy.Type.SOCKS, java.net.InetSocketAddress("127.0.0.1", 7777))
                        
                        val conn = url.openConnection(proxy) as java.net.HttpURLConnection
                        conn.connectTimeout = 30000
                        conn.setRequestProperty("User-Agent", "MiniZIVPN-Updater")
                        
                        val input = conn.inputStream
                        val output = java.io.FileOutputStream(destPath)
                        val buffer = ByteArray(8192)
                        var bytesRead: Int
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                        }
                        output.close()
                        input.close()
                        
                        uiHandler.post { result.success("OK") }
                    } catch (e: Exception) {
                        Log.e("ZIVPN-Updater", "SOCKS5 Download failed: ${e.message}")
                        uiHandler.post { result.error("ERR", e.message, null) }
                    }
                }.start()
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
                prefs.putString("flutter.hysteria_recv_window", call.argument<String>("hysteria_recv_window") ?: "327680")
                prefs.putString("flutter.hysteria_recv_conn", call.argument<String>("hysteria_recv_conn") ?: "131072")
                prefs.putString("flutter.proxy_id", call.argument<String>("proxy_id") ?: "default")

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
            } else if (call.method == "nativePing") {
                val host = call.argument<String>("host") ?: "8.8.8.8"
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 3000
                Thread {
                    val rtt = runNativePing(host, timeoutMs)
                    uiHandler.post { result.success(rtt) }
                }.start()
            } else if (call.method == "hasUsageStatsPermission") {
                result.success(proxyUsageManager.hasUsageStatsPermission())
            } else if (call.method == "requestUsageStatsPermission") {
                try {
                    startActivity(proxyUsageManager.buildUsageStatsSettingsIntent())
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            } else if (call.method == "startProxyUsageSession") {
                val proxyId = call.argument<String>("proxyId") ?: "default"
                val started = proxyUsageManager.startConnection(proxyId)
                if (started) {
                    lastNetworkStatsTotal = 0L
                }
                result.success(started)
            } else if (call.method == "getProxyUsageDelta") {
                val proxyId = call.argument<String>("proxyId")
                result.success(proxyUsageManager.computeCurrentDelta(proxyId))
            } else if (call.method == "commitProxyUsageDelta") {
                val proxyId = call.argument<String>("proxyId")
                result.success(proxyUsageManager.commitDelta(proxyId))
            } else if (call.method == "getProxyUsageTotal") {
                val proxyId = call.argument<String>("proxyId") ?: "default"
                result.success(proxyUsageManager.getTotalBytes(proxyId))
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

    private fun runNativePing(host: String, timeoutMs: Int): Int {
        return try {
            val timeoutSec = (timeoutMs / 1000).coerceAtLeast(1)
            val process = ProcessBuilder("/system/bin/ping", "-c", "1", "-W", timeoutSec.toString(), host)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            process.waitFor()

            val regex = Regex("""time=([0-9]+(?:\.[0-9]+)?)""")
            val match = regex.find(output)
            if (match != null) {
                val value = match.groupValues[1].toDoubleOrNull()
                return if (value != null) value.toInt() else -1
            }
            -1
        } catch (_: Exception) {
            -1
        }
    }

    private fun startProxyUsageTracking() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val proxyId = prefs.getString("flutter.proxy_id", "default") ?: "default"

        if (proxyUsageManager.hasUsageStatsPermission()) {
            val started = proxyUsageManager.startConnection(proxyId)
            if (started) {
                lastNetworkStatsTotal = 0L
                sendToLog("[USAGE] Session baseline captured for proxy: $proxyId")
            }
        } else {
            sendToLog("[USAGE] PACKAGE_USAGE_STATS permission not granted.")
        }
    }

    private fun stopProxyUsageTracking() {
        val activeProxy = proxyUsageManager.getActiveProxyId() ?: return
        val total = proxyUsageManager.commitDelta(activeProxy)
        sendToLog("[USAGE] Proxy $activeProxy total: ${proxyUsageManager.formatBytes(total)}")
        proxyUsageManager.clearActiveSession()
        lastNetworkStatsTotal = 0L
    }

    private fun startStatsTimer() {
        stopStatsTimer()
        statsTimer = Timer()
        val uid = android.os.Process.myUid()
        var lastRxFallback = TrafficStats.getUidRxBytes(uid)
        var lastTxFallback = TrafficStats.getUidTxBytes(uid)

        statsTimer?.schedule(object : TimerTask() {
            override fun run() {
                val proxyId = proxyUsageManager.getActiveProxyId()

                if (proxyId != null && proxyUsageManager.hasUsageStatsPermission()) {
                    val currentTotal = proxyUsageManager.computeCurrentDelta(proxyId)
                    val speed = (currentTotal - lastNetworkStatsTotal).coerceAtLeast(0L)
                    lastNetworkStatsTotal = currentTotal

                    // Split speed as rx/tx approximation for existing Flutter UI channel
                    val rxSpeed = speed / 2
                    val txSpeed = speed - rxSpeed
                    uiHandler.post {
                        statsSink?.success("$rxSpeed|$txSpeed")
                    }
                    return
                }

                // Fallback when usage stats permission unavailable
                val currentRx = TrafficStats.getUidRxBytes(uid)
                val currentTx = TrafficStats.getUidTxBytes(uid)

                val rxSpeed = currentRx - lastRxFallback
                val txSpeed = currentTx - lastTxFallback

                lastRxFallback = currentRx
                lastTxFallback = currentTx

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
            startProxyUsageTracking()
        }
    }

    private fun stopVpn() {
        val serviceIntent = Intent(this, ZivpnService::class.java)
        serviceIntent.action = ZivpnService.ACTION_DISCONNECT
        startService(serviceIntent)
        stopProxyUsageTracking()
        sendToLog("VPN Service stopped.")
    }

    private fun registerAutoPilotChannel(flutterEngine: FlutterEngine) {
        val channel = "com.minizivpn.app/service"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    val serviceIntent = Intent(this, KeepAliveService::class.java)
                    serviceIntent.putExtra(KeepAliveService.EXTRA_NOTIFICATION_MODE, "jet")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success("Started")
                }
                "updateForegroundMode" -> {
                    val mode = call.argument<String>("mode") ?: "jet"
                    val serviceIntent = Intent(this, KeepAliveService::class.java)
                    serviceIntent.putExtra(KeepAliveService.EXTRA_NOTIFICATION_MODE, mode)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success("Updated")
                }
                "stopForeground" -> {
                    val serviceIntent = Intent(this, KeepAliveService::class.java)
                    stopService(serviceIntent)
                    result.success("Stopped")
                }
                "cancelPingIcon" -> {
                    result.success(cancelPingNotification())
                }
                "updatePingIcon" -> {
                    val text = call.argument<String>("text") ?: "?"
                    val title = call.argument<String>("title") ?: "PING Monitor"
                    val body = call.argument<String>("body") ?: ""
                    val updated = updatePingNotification(text, title, body)
                    if (updated) {
                        result.success(true)
                    } else {
                        result.error("NOTIFICATION_UPDATE_FAILED", "Failed to update ping icon notification", null)
                    }
                }
                "minimizeApp" -> {
                    moveTaskToBack(true)
                    result.success("Minimized")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun cancelPingNotification(): Boolean {
        return try {
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.cancel(1001)
            true
        } catch (e: Exception) {
            Log.e("AutoPilot", "Failed to cancel ping notification", e)
            false
        }
    }

    private fun updatePingNotification(text: String, title: String, body: String): Boolean {
        Log.d("ZIVPN-Bitmap", "Updating ping icon: $text")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val density = resources.displayMetrics.density
                val iconHeight = (22f * density).toInt().coerceIn(88, 140)
                val iconWidth = (64f * density).toInt().coerceIn(iconHeight * 2, 360)
                val bitmap = Bitmap.createBitmap(iconWidth, iconHeight, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)

                val latencyText = text.trim().ifEmpty { "?" }
                val unitText = "ms"

                val numberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    textAlign = Paint.Align.LEFT
                    typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                }
                val unitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    textAlign = Paint.Align.LEFT
                    typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
                }

                val padding = iconHeight * 0.06f
                val contentWidth = iconWidth - (padding * 2f)
                val maxTextHeight = iconHeight * 0.90f
                val gapRatio = 0.05f

                var numberSize = iconHeight * 0.88f
                var unitSize = numberSize * 0.56f
                var fitFound = false

                for (i in 0 until 24) {
                    numberPaint.textSize = numberSize
                    unitPaint.textSize = unitSize

                    val numberWidth = numberPaint.measureText(latencyText)
                    val unitWidth = unitPaint.measureText(unitText)
                    val gap = numberSize * gapRatio
                    val totalWidth = numberWidth + gap + unitWidth

                    val numberMetrics = numberPaint.fontMetrics
                    val unitMetrics = unitPaint.fontMetrics
                    val ascent = minOf(numberMetrics.ascent, unitMetrics.ascent)
                    val descent = maxOf(numberMetrics.descent, unitMetrics.descent)
                    val textHeight = descent - ascent

                    if (totalWidth <= contentWidth && textHeight <= maxTextHeight) {
                        fitFound = true
                        break
                    }

                    numberSize *= 0.95f
                    unitSize = numberSize * 0.56f
                }

                if (!fitFound) {
                    numberSize = iconHeight * 0.50f
                    unitSize = numberSize * 0.56f
                }

                numberPaint.textSize = numberSize
                unitPaint.textSize = unitSize

                val numberWidth = numberPaint.measureText(latencyText)
                val unitWidth = unitPaint.measureText(unitText)
                val gap = numberSize * gapRatio
                val totalWidth = numberWidth + gap + unitWidth

                val numberMetrics = numberPaint.fontMetrics
                val unitMetrics = unitPaint.fontMetrics
                val ascent = minOf(numberMetrics.ascent, unitMetrics.ascent)
                val descent = maxOf(numberMetrics.descent, unitMetrics.descent)
                val baseline = (iconHeight / 2f) - ((ascent + descent) / 2f)

                val startX = ((iconWidth - totalWidth) / 2f).coerceAtLeast(padding)

                canvas.drawText(latencyText, startX, baseline, numberPaint)
                canvas.drawText(unitText, startX + numberWidth + gap, baseline, unitPaint)

                val icon = Icon.createWithBitmap(bitmap)

                // Ensure channel exists
                val channelId = "ping_notifications"
                val notificationManager = getSystemService(NotificationManager::class.java)
                
                if (notificationManager != null) {
                    val channel = NotificationChannel(channelId, "AutoPilot Status", NotificationManager.IMPORTANCE_LOW)
                    channel.setShowBadge(false)
                    notificationManager.createNotificationChannel(channel)
                }

                // Build notification
                val builder = Notification.Builder(this, channelId)
                    .setSmallIcon(icon)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setOnlyAlertOnce(true)
                    .setOngoing(true)
                    .setShowWhen(true)
                    .setWhen(System.currentTimeMillis())
                    .setCategory(Notification.CATEGORY_SERVICE)
                    .setLocalOnly(true)
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                }
                
                // Intent to open app
                val intent = Intent(this, MainActivity::class.java)
                val pendingIntent = android.app.PendingIntent.getActivity(
                    this, 0, intent, android.app.PendingIntent.FLAG_IMMUTABLE
                )
                builder.setContentIntent(pendingIntent)

                notificationManager?.notify(1001, builder.build()) // ID 1001 for Ping Icon
                return true
            } catch (e: Exception) {
                Log.e("AutoPilot", "Icon update failed", e)
                return false
            }
        }
        return false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_CODE) {
            if (resultCode == RESULT_OK) {
                val serviceIntent = Intent(this, ZivpnService::class.java)
                serviceIntent.action = ZivpnService.ACTION_CONNECT
                ContextCompat.startForegroundService(this, serviceIntent)
                sendToLog("VPN permission granted. Starting service.")
                startProxyUsageTracking()
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
