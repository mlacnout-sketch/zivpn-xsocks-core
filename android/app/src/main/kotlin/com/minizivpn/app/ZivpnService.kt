package com.minizivpn.app

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import android.app.PendingIntent
import android.app.Service
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import android.content.pm.ServiceInfo
import java.net.InetAddress
import java.net.Proxy
import java.net.InetSocketAddress
import java.util.LinkedList
import androidx.annotation.Keep
import java.io.File
import org.json.JSONObject
import com.minizivpn.app.R

import java.io.BufferedReader
import java.io.InputStreamReader

import android.os.PowerManager
import com.minizivpn.app.NativeSystem

import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * ZIVPN TunService
 * Handles the VpnService interface and integrates with tun2socks via JNI.
 */
@Keep
class ZivpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "com.minizivpn.app.CONNECT"
        const val ACTION_DISCONNECT = "com.minizivpn.app.DISCONNECT"
        const val ACTION_LOG = "com.minizivpn.app.LOG"
        const val CHANNEL_ID = "ZIVPN_SERVICE_CHANNEL"
        const val NOTIFICATION_ID = 1
        const val LOCAL_SOCKS_PORT = 7777
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val processes = mutableListOf<Process>()
    private var wakeLock: PowerManager.WakeLock? = null
    private var pingExecutor: ScheduledExecutorService? = null
    
    // Class-level properties to be accessible within inner classes/lambdas
    private var consecutiveFailures = 0
    private var sessionResetCount = 0

    private fun acquireCpuWakeLock() {
        if (wakeLock?.isHeld == true) return

        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MiniZivpn::CoreWakelock").apply {
                setReferenceCounted(false)
                acquire(10 * 60 * 1000L)
            }
            logToApp("CPU Wakelock acquired")
        } catch (e: SecurityException) {
            logToApp("CPU Wakelock failed: missing permission (${e.message})")
            wakeLock = null
        } catch (e: Exception) {
            logToApp("CPU Wakelock failed: ${e.message}")
            wakeLock = null
        }
    }

    private fun releaseCpuWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                logToApp("CPU Wakelock released")
            }
        } catch (e: Exception) {
            logToApp("CPU Wakelock release warning: ${e.message}")
        } finally {
            wakeLock = null
        }
    }

    private fun logToApp(msg: String) {
        val intent = Intent(ACTION_LOG)
        intent.putExtra("message", msg)
        sendBroadcast(intent)
        Log.d("ZIVPN-Core", msg)
    }

    private fun captureProcessLog(process: Process, name: String) {
        Thread {
            try {
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    logToApp("[$name] $line")
                }
            } catch (e: Exception) {
                logToApp("[$name] Log stream closed: ${e.message}")
            }
        }.start()
        
        Thread {
            try {
                val reader = BufferedReader(InputStreamReader(process.errorStream))
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    logToApp("[$name-ERR] $line")
                }
            } catch (e: Exception) {}
        }.start()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // ALWAYS call startForeground as early as possible on Android 8.0+
        startForegroundService()

        when (intent?.action) {
            ACTION_CONNECT -> {
                connect()
                return START_STICKY
            }
            ACTION_DISCONNECT -> {
                disconnect()
                return START_NOT_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val restartServiceIntent = Intent(applicationContext, this.javaClass)
        restartServiceIntent.setPackage(packageName)
        restartServiceIntent.action = ACTION_CONNECT // Ensure it tries to reconnect
        
        val restartServicePendingIntent = PendingIntent.getService(
            applicationContext, 1, restartServiceIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmService = applicationContext.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        alarmService.set(
            android.app.AlarmManager.ELAPSED_REALTIME,
            System.currentTimeMillis() + 1000,
            restartServicePendingIntent
        )
        Log.d("ZIVPN-Core", "App swiped from recent tasks. Scheduling restart.")
        super.onTaskRemoved(rootIntent)
    }
    
    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ZIVPN Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MiniZIVPN Running")
            .setContentText("VPN Service is active")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
             startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
             startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun getPrefString(prefs: android.content.SharedPreferences, key: String, def: String): String {
        return prefs.getString("flutter.$key", null) ?: prefs.getString(key, def) ?: def
    }

    private fun getPrefInt(prefs: android.content.SharedPreferences, key: String, def: Int): Int {
        if (prefs.contains("flutter.$key")) return try { prefs.getInt("flutter.$key", def) } catch(e: Exception) { (prefs.getString("flutter.$key", null))?.toIntOrNull() ?: def }
        return prefs.getInt(key, def)
    }

    private fun getPrefBool(prefs: android.content.SharedPreferences, key: String, def: Boolean): Boolean {
        return if (prefs.contains("flutter.$key")) prefs.getBoolean("flutter.$key", def) else prefs.getBoolean(key, def)
    }


    private fun getPrefIntFlexible(prefs: android.content.SharedPreferences, key: String, def: Int): Int {
        if (prefs.contains("flutter.$key")) {
            return try {
                prefs.getInt("flutter.$key", def)
            } catch (e: Exception) {
                prefs.getString("flutter.$key", null)?.toIntOrNull() ?: def
            }
        }
        return try {
            prefs.getInt(key, def)
        } catch (e: Exception) {
            prefs.getString(key, null)?.toIntOrNull() ?: def
        }
    }

    private fun clamp(value: Int, min: Int, max: Int): Int {
        return when {
            value < min -> min
            value > max -> max
            else -> value
        }
    }

    private fun connect() {
        if (vpnInterface != null) return

        Thread {
            try {
                Log.i("ZIVPN-Tun", "Initializing ZIVPN (native tun2socks)...")
                
                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                
                val ip = getPrefString(prefs, "server_ip", "")
                val range = getPrefString(prefs, "server_range", "")
                val pass = getPrefString(prefs, "server_pass", "")
                val obfs = getPrefString(prefs, "server_obfs", "")
                val multiplier = 1.0f // Fixed
                val mtu = getPrefInt(prefs, "mtu", 1500)
                val logLevel = getPrefString(prefs, "log_level", "info")
                val coreCount = getPrefInt(prefs, "core_count", 4)
                val useWakelock = getPrefBool(prefs, "cpu_wakelock", false)

                if (useWakelock) {
                    acquireCpuWakeLock()
                }

                // 1. START HYSTERIA & LOAD BALANCER
                startCores(ip, range, pass, obfs, multiplier.toDouble(), coreCount, logLevel)

                val pendingIntent = PendingIntent.getActivity(
                    this, 0, Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                // 2. Build VPN Interface
                val builder = Builder()
                builder.setSession("MiniZivpn")
                builder.setConfigureIntent(pendingIntent)
                builder.setMtu(mtu)
                
                // DYNAMIC ROUTING: Exclude Server IP
                val serverHost = getPrefString(prefs, "server_ip", "")
                if (serverHost.isNotEmpty()) {
                    logToApp("Resolving server: $serverHost")
                    val resolvedIp = try {
                        InetAddress.getByName(serverHost).hostAddress
                    } catch (e: Exception) {
                        serverHost
                    }
                    
                    logToApp("Excluding server IP: $resolvedIp")
                    val dynamicRoutes = RoutingUtils.calculateDynamicRoutes(resolvedIp)
                    for (route in dynamicRoutes) {
                        try {
                            builder.addRoute(route.first, route.second)
                        } catch (e: Exception) {}
                    }
                } else {
                    builder.addRoute("0.0.0.0", 1)
                    builder.addRoute("128.0.0.0", 1)
                }
                
                // Apps Filter
                val filterApps = getPrefBool(prefs, "filter_apps", false)
                val bypassMode = getPrefBool(prefs, "bypass_mode", false)
                val appsList = getPrefString(prefs, "apps_list", "")

                if (filterApps && appsList.isNotEmpty()) {
                    val appPackages = appsList.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                    for (pkg in appPackages) {
                        try {
                            if (bypassMode) builder.addDisallowedApplication(pkg)
                            else builder.addAllowedApplication(pkg)
                        } catch (e: Exception) {}
                    }
                }

                builder.addRoute("169.254.1.0", 24)
                builder.addRoute("198.18.0.0", 15)
                builder.addDisallowedApplication(packageName)
                builder.addDnsServer("169.254.1.2")
                builder.addAddress("169.254.1.1", 24)

                vpnInterface = builder.establish()
                val fd = vpnInterface?.fd ?: return@Thread

                // 3. Start Pdnsd & tun2socks
                val pdnsdPort = getPrefIntFlexible(prefs, "pdnsd_port", 8091)
                startNativeEngines(fd, mtu, logLevel, prefs, pdnsdPort)

            } catch (e: Exception) {
                logToApp("Connect Error: ${e.message}")
                stopSelf()
            }
        }.start()
    }

    private fun startNativeEngines(fd: Int, mtu: Int, logLevel: String, prefs: android.content.SharedPreferences, pdnsdPort: Int) {
        // Logika pdnsd dan tun2socks (yang tadinya ada di connect) 
        // Saya buat fungsi bantuan agar kode lebih bersih
        try {
            val cacheDir = File(cacheDir, "pdnsd_cache")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            
            val upstreamDns = getPrefString(prefs, "upstream_dns", "208.67.222.222")
            val profile = getPrefString(prefs, "native_perf_profile", "balanced")

            var tcpSndBuf = getPrefIntFlexible(prefs, "tcp_snd_buf", 65535)
            var tcpWnd = getPrefIntFlexible(prefs, "tcp_wnd", 65535)
            var socksBuf = getPrefIntFlexible(prefs, "socks_buf", 65536)
            var udpgwMaxConn = getPrefIntFlexible(prefs, "udpgw_max_connections", 512)
            var udpgwBufSize = getPrefIntFlexible(prefs, "udpgw_buffer_size", 32)
            var pdnsdPermCache = getPrefIntFlexible(prefs, "pdnsd_cache_entries", 2048)
            var pdnsdTimeout = getPrefIntFlexible(prefs, "pdnsd_timeout_sec", 10)
            var pdnsdVerbosity = getPrefIntFlexible(prefs, "pdnsd_verbosity", 2)

            if (profile == "throughput") {
                tcpSndBuf = 65535
                tcpWnd = 65535
                socksBuf = 131072
                udpgwMaxConn = 1024
                udpgwBufSize = 64
                pdnsdPermCache = 4096
                pdnsdTimeout = 8
                pdnsdVerbosity = 1
            } else if (profile == "latency") {
                tcpSndBuf = 32768
                tcpWnd = 32768
                socksBuf = 65536
                udpgwMaxConn = 256
                udpgwBufSize = 16
                pdnsdPermCache = 2048
                pdnsdTimeout = 5
                pdnsdVerbosity = 1
            }

            tcpSndBuf = clamp(tcpSndBuf, 4096, 65535)
            tcpWnd = clamp(tcpWnd, 4096, 65535)
            socksBuf = clamp(socksBuf, 4096, 524288)
            udpgwMaxConn = clamp(udpgwMaxConn, 16, 4096)
            udpgwBufSize = clamp(udpgwBufSize, 4, 256)
            pdnsdPermCache = clamp(pdnsdPermCache, 256, 32768)
            pdnsdTimeout = clamp(pdnsdTimeout, 3, 30)
            pdnsdVerbosity = clamp(pdnsdVerbosity, 0, 3)

            val pdnsdConf = Pdnsd.writeConfig(
                context = this,
                listenPort = pdnsdPort,
                upstreamDns = upstreamDns,
                tuning = PdnsdTuning(
                    permCache = pdnsdPermCache,
                    timeout = pdnsdTimeout,
                    minTtl = getPrefString(prefs, "pdnsd_min_ttl", "15m"),
                    maxTtl = getPrefString(prefs, "pdnsd_max_ttl", "1w"),
                    queryMethod = getPrefString(prefs, "pdnsd_query_method", "tcp_only"),
                    verbosity = pdnsdVerbosity
                )
            )
            val pdnsdBin = Pdnsd.getExecutable(this)
            File(pdnsdBin).setExecutable(true)

            val pdnsdCmd = listOf(pdnsdBin, "-g", "-c", pdnsdConf)
            val pdnsdProc = ProcessBuilder(pdnsdCmd).directory(filesDir).start()
            processes.add(pdnsdProc)
            captureProcessLog(pdnsdProc, "Pdnsd")

            val libDir = applicationInfo.nativeLibraryDir
            val tun2socksBin = File(libDir, "libtun2socks.so").absolutePath
            val tsLogLevel = when (logLevel) { "debug" -> "debug"; "error" -> "error"; "silent" -> "none"; else -> "info" }

            val useUdpgw = getPrefBool(prefs, "enable_udpgw", true)
            val udpgwPort = getPrefString(prefs, "udpgw_port", "7300")

            val tunCmd = arrayListOf(
                tun2socksBin, "--netif-ipaddr", "169.254.1.2", "--netif-netmask", "255.255.255.0",
                "--socks-server-addr", "127.0.0.1:7777", "--tunmtu", mtu.toString(),
                "--loglevel", tsLogLevel, "--dnsgw", "169.254.1.1:$pdnsdPort", "--fake-proc"
            )

            tunCmd.add("--tcp-snd-buf"); tunCmd.add(tcpSndBuf.toString())
            tunCmd.add("--tcp-wnd"); tunCmd.add(tcpWnd.toString())
            tunCmd.add("--socks-buf"); tunCmd.add(socksBuf.toString())

            if (useUdpgw) {
                tunCmd.add("--udpgw-remote-server-addr"); tunCmd.add("127.0.0.1:$udpgwPort")
                tunCmd.add("--udpgw-max-connections"); tunCmd.add(udpgwMaxConn.toString())
                tunCmd.add("--udpgw-connection-buffer-size"); tunCmd.add(udpgwBufSize.toString())
                if (getPrefBool(prefs, "udpgw_transparent_dns", false)) {
                    tunCmd.add("--udpgw-transparent-dns")
                }
            }

            logToApp("Native profile=$profile tcpWnd=$tcpWnd socksBuf=$socksBuf udpgwMax=$udpgwMaxConn pdnsdCache=$pdnsdPermCache")

            val tunProc = ProcessBuilder(tunCmd).directory(filesDir).start()
            processes.add(tunProc)
            captureProcessLog(tunProc, "Tun2Socks")

            Thread.sleep(1000)
            if (NativeSystem.sendfd(fd) == 0) {
                logToApp("VPN Engine Running.")
                prefs.edit().putBoolean("flutter.vpn_running", true).apply()
                val pingInterval = prefs.getInt("ping_interval", 3)
                val rawTarget = getPrefString(prefs, "ping_target", "http://connectivitycheck.gstatic.com/generate_204")
                val finalTarget = if (rawTarget.startsWith("http")) rawTarget else "http://$rawTarget"
                
                if (pingInterval > 0) startPingTimer(finalTarget, pingInterval)
            }
        } catch (e: Exception) {
            logToApp("Native Engine Error: ${e.message}")
        }
    }

    private fun startCores(ip: String, range: String, pass: String, obfs: String, multiplier: Double, coreCount: Int, logLevel: String) {
        val libDir = applicationInfo.nativeLibraryDir
        val libUz = File(libDir, "libuz.so").absolutePath
        val libLoad = File(libDir, "libload.so").absolutePath
        
        val baseConn = 131072
        val baseWin = 327680
        val dynamicConn = (baseConn * multiplier).toInt()
        val dynamicWin = (baseWin * multiplier).toInt()
        
        val ports = (0 until coreCount).map { 20080 + it }
        val tunnelTargets = mutableListOf<String>()

        // Map log level for Hysteria
        val hyLogLevel = when(logLevel) {
            "silent" -> "disable"
            "error" -> "error"
            "debug" -> "debug"
            else -> "info"
        }

        for (port in ports) {
            val hyConfig = JSONObject()
            hyConfig.put("server", "$ip:$range")
            hyConfig.put("obfs", obfs)
            hyConfig.put("auth", pass)
            hyConfig.put("loglevel", hyLogLevel)
            
            val socks5Json = JSONObject()
            socks5Json.put("listen", "127.0.0.1:$port")
            hyConfig.put("socks5", socks5Json)
            
            hyConfig.put("insecure", true)
            hyConfig.put("recvwindowconn", dynamicConn)
            hyConfig.put("recvwindow", dynamicWin)
            
            val hyCmd = arrayListOf(libUz, "-s", obfs, "--config", hyConfig.toString())
            val hyPb = ProcessBuilder(hyCmd)
            hyPb.directory(filesDir)
            hyPb.environment()["LD_LIBRARY_PATH"] = libDir
            hyPb.redirectErrorStream(true)
            
            val p = hyPb.start()
            processes.add(p)
            captureProcessLog(p, "Hysteria-$port")
            tunnelTargets.add("127.0.0.1:$port")
        }
        
        logToApp("Waiting for cores to warm up...")
        Thread.sleep(1500)

        val lbCmd = mutableListOf(libLoad, "-lport", "7777", "-tunnel")
        lbCmd.addAll(tunnelTargets)
        
        val lbPb = ProcessBuilder(lbCmd)
        lbPb.directory(filesDir)
        lbPb.environment()["LD_LIBRARY_PATH"] = libDir
        lbPb.redirectErrorStream(true)
        
        val lbProcess = lbPb.start()
        processes.add(lbProcess)
        captureProcessLog(lbProcess, "LoadBalancer")
        logToApp("Load Balancer active on port 7777")
    }

    private fun disconnect() {
        Log.i("ZIVPN-Tun", "Stopping VPN and cores...")
        
        stopPingTimer()

        releaseCpuWakeLock()
        
        // Stop tun2socks process explicitly if it's in the list (it is)
        
        processes.forEach { 
            try {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    it.destroyForcibly()
                } else {
                    it.destroy()
                }
            } catch(e: Exception){} 
        }
        processes.clear()

        // Optimized: Run cleanup in background to prevent ANR
        // Added libtun2socks.so and libpdnsd.so to cleanup
        Thread {
            try {
                val cleanupCmd = arrayOf("sh", "-c", "pkill -9 libuz; pkill -9 libload; pkill -9 libuz.so; pkill -9 libload.so; pkill -9 libtun2socks.so; pkill -9 libpdnsd.so")
                Runtime.getRuntime().exec(cleanupCmd).waitFor()
            } catch (e: Exception) {}
        }.start()

        vpnInterface?.close()
        vpnInterface = null
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        prefs.edit().putBoolean("flutter.vpn_running", false).apply()
        
        stopForeground(true)
        stopSelf()
    }

    private fun startPingTimer(target: String, intervalSeconds: Int) {
        stopPingTimer()
        consecutiveFailures = 0
        sessionResetCount = 0
        pingExecutor = Executors.newSingleThreadScheduledExecutor()
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val maxFail = getPrefInt(prefs, "max_fail_count", 3)
        val autoReset = getPrefBool(prefs, "auto_reset", false)
        val pingTimeout = getPrefInt(prefs, "ping_timeout", 5)
        
        pingExecutor?.scheduleAtFixedRate({
            val start = System.currentTimeMillis()
            try {
                val url = java.net.URL(target)
                val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", LOCAL_SOCKS_PORT))
                val conn = url.openConnection(proxy) as java.net.HttpURLConnection
                
                conn.connectTimeout = pingTimeout * 1000
                conn.readTimeout = pingTimeout * 1000
                conn.requestMethod = "HEAD"
                
                val responseCode = conn.responseCode
                val duration = System.currentTimeMillis() - start
                
                if (responseCode == 200 || responseCode == 204) {
                    consecutiveFailures = 0
                    sessionResetCount = 0
                    logToApp("[PING] $target: $responseCode (${duration}ms)")
                } else {
                    throw Exception("HTTP $responseCode")
                }
            } catch (e: Exception) {
                consecutiveFailures++
                logToApp("[PING] Failed: ${e.message} ($consecutiveFailures/$maxFail)")
                
                if (autoReset && consecutiveFailures >= maxFail) {
                    if (sessionResetCount < 5) {
                        logToApp("[CONNECTION_LOST] Max failures reached. Triggering Auto Reset (#${sessionResetCount + 1})...")
                        sessionResetCount++
                    } else {
                        logToApp("[AutoPilot] ⛔ Gave up after 5 resets. Internet seems permanently dead.")
                    }
                    consecutiveFailures = 0
                }
            }
        }, 0, intervalSeconds.toLong(), TimeUnit.SECONDS)
        
        logToApp("Auto-Ping started every $intervalSeconds seconds (Timeout: ${pingTimeout}s)")
    }

    private fun stopPingTimer() {
        pingExecutor?.shutdownNow()
        pingExecutor = null
    }

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }
}
