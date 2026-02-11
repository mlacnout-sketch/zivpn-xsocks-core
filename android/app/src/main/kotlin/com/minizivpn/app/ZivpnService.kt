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
import java.util.LinkedList
import androidx.annotation.Keep
import java.io.File
import org.json.JSONObject

import java.io.BufferedReader
import java.io.InputStreamReader

import android.os.PowerManager
import com.minizivpn.app.NativeSystem

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
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val processes = mutableListOf<Process>()
    private var wakeLock: PowerManager.WakeLock? = null
    private var pingTimer: java.util.Timer? = null

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
        if (intent?.action == ACTION_CONNECT) {
             startForegroundService()
        }
        
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
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
             startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
             startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
             startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun connect() {
        if (vpnInterface != null) return

        Thread {
            try {
                Log.i("ZIVPN-Tun", "Initializing ZIVPN (native tun2socks)...")
                
                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                
                val ip = prefs.getString("server_ip", "") ?: ""
                val range = prefs.getString("server_range", "") ?: ""
                val pass = prefs.getString("server_pass", "") ?: ""
                val obfs = prefs.getString("server_obfs", "") ?: ""
                val multiplier = prefs.getFloat("multiplier", 1.0f)
                val mtu = prefs.getInt("mtu", 1500)
                val logLevel = prefs.getString("log_level", "info") ?: "info"
                val coreCount = prefs.getInt("core_count", 4)
                val useWakelock = prefs.getBoolean("cpu_wakelock", false)

                if (useWakelock) {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MiniZivpn::CoreWakelock")
                    wakeLock?.acquire()
                    logToApp("CPU Wakelock acquired")
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
                val serverHost = prefs.getString("server_ip", "") ?: ""
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
                val filterApps = prefs.getBoolean("filter_apps", false)
                val bypassMode = prefs.getBoolean("bypass_mode", false)
                val appsList = prefs.getString("apps_list", "") ?: ""

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
                startNativeEngines(fd, mtu, logLevel, prefs, 8091)

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
            
            val upstreamDns = prefs.getString("upstream_dns", "208.67.222.222") ?: "208.67.222.222"
            val pdnsdConf = Pdnsd.writeConfig(this, pdnsdPort, upstreamDns)
            val pdnsdBin = Pdnsd.getExecutable(this)
            File(pdnsdBin).setExecutable(true)

            val pdnsdCmd = listOf(pdnsdBin, "-g", "-c", pdnsdConf)
            val pdnsdProc = ProcessBuilder(pdnsdCmd).directory(filesDir).start()
            processes.add(pdnsdProc)
            captureProcessLog(pdnsdProc, "Pdnsd")

            val libDir = applicationInfo.nativeLibraryDir
            val tun2socksBin = File(libDir, "libtun2socks.so").absolutePath
            val tsLogLevel = when (logLevel) { "debug" -> "debug"; "error" -> "error"; "silent" -> "none"; else -> "info" }

            val useUdpgw = prefs.getBoolean("enable_udpgw", true)
            val udpgwMode = prefs.getString("udpgw_mode", "relay") ?: "relay"
            val udpgwPort = prefs.getString("udpgw_port", "7300") ?: "7300"

            val tunCmd = arrayListOf(
                tun2socksBin, "--netif-ipaddr", "169.254.1.2", "--netif-netmask", "255.255.255.0",
                "--socks-server-addr", "127.0.0.1:7777", "--tunmtu", mtu.toString(),
                "--loglevel", tsLogLevel, "--dnsgw", "169.254.1.1:$pdnsdPort", "--fake-proc"
            )
            
            if (useUdpgw) {
                if (udpgwMode == "standard") {
                    tunCmd.add("--udpgw-remote-server-addr"); tunCmd.add("127.0.0.1:$udpgwPort")
                } else { tunCmd.add("--enable-udprelay") }
                tunCmd.add("--udprelay-max-connections"); tunCmd.add("512")
            }

            val tunProc = ProcessBuilder(tunCmd).directory(filesDir).start()
            processes.add(tunProc)
            captureProcessLog(tunProc, "Tun2Socks")

            Thread.sleep(1000)
            if (NativeSystem.sendfd(fd) == 0) {
                logToApp("VPN Engine Running.")
                prefs.edit().putBoolean("flutter.vpn_running", true).apply()
                val pingInterval = prefs.getInt("ping_interval", 3)
                if (pingInterval > 0) startPingTimer(prefs.getString("ping_target", "") ?: "", pingInterval)
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

        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
            logToApp("CPU Wakelock released")
        }
        wakeLock = null
        
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
        pingTimer = java.util.Timer()
        val intervalMillis = (intervalSeconds * 1000).toLong()
        
        pingTimer?.schedule(object : java.util.TimerTask() {
            override fun run() {
                try {
                    val url = java.net.URL(target)
                    val conn = url.openConnection() as java.net.HttpURLConnection
                    conn.connectTimeout = 5000
                    conn.readTimeout = 5000
                    conn.requestMethod = "GET"
                    val responseCode = conn.responseCode
                    Log.d("ZIVPN-Ping", "Auto-Ping to $target: $responseCode")
                } catch (e: Exception) {
                    Log.e("ZIVPN-Ping", "Auto-Ping failed: ${e.message}")
                }
            }
        }, intervalMillis, intervalMillis)
        logToApp("Auto-Ping started every $intervalSeconds seconds to $target")
    }

    private fun stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = null
    }

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }
}
