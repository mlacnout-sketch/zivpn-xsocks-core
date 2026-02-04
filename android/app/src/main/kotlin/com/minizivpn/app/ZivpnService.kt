package com.minizivpn.app

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import android.app.PendingIntent
import java.net.InetAddress
import java.util.LinkedList
import androidx.annotation.Keep
import mobile.Mobile
import java.io.File
import org.json.JSONObject

import java.io.BufferedReader
import java.io.InputStreamReader

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
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val processes = mutableListOf<Process>()

    private val tunLogger = object : mobile.LogHandler {
        override fun writeLog(message: String?) {
            if (message != null) {
                logToApp("[Tun2Socks] $message")
            }
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

    private fun connect() {
        if (vpnInterface != null) return

        Log.i("ZIVPN-Tun", "Initializing ZIVPN (tun2socks engine)...")
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        
        val ip = prefs.getString("server_ip", "") ?: ""
        val range = prefs.getString("server_range", "") ?: ""
        val pass = prefs.getString("server_pass", "") ?: ""
        val obfs = prefs.getString("server_obfs", "") ?: ""
        val multiplier = prefs.getFloat("multiplier", 1.0f)
        val mtu = prefs.getInt("mtu", 1500)

        // 1. START HYSTERIA & LOAD BALANCER
        try {
            startCores(ip, range, pass, obfs, multiplier.toDouble())
        } catch (e: Exception) {
            Log.e("ZIVPN-Tun", "Failed to start cores: ${e.message}")
            stopSelf()
            return
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 2. Build VPN Interface
        val builder = Builder()
        builder.setSession("MiniZivpn")
        builder.setConfigureIntent(pendingIntent)
        builder.setMtu(mtu)
        
        // GLOBAL ROUTING: Catch EVERYTHING
        try {
            builder.addRoute("0.0.0.0", 0)
            // Handle Fake-IP range (198.18.0.0/15) to prevent "host unreachable" errors
            builder.addRoute("198.18.0.0", 15)
        } catch (e: Exception) {
            Log.e("ZIVPN-Tun", "Failed to add global route, falling back to subnets")
            // Fallback to stable subnets if 0.0.0.0/0 is rejected by system
            val subnets = listOf(
                "0.0.0.0" to 5, "8.0.0.0" to 7, "11.0.0.0" to 8, "12.0.0.0" to 6,
                "16.0.0.0" to 4, "32.0.0.0" to 3, "64.0.0.0" to 2, "128.0.0.0" to 3,
                "160.0.0.0" to 5, "168.0.0.0" to 6, "176.0.0.0" to 4, "192.0.0.0" to 9,
                "192.128.0.0" to 11, "192.160.0.0" to 13, "192.169.0.0" to 16,
                "192.170.0.0" to 15, "192.172.0.0" to 14, "193.0.0.0" to 8,
                "194.0.0.0" to 7, "196.0.0.0" to 6, "200.0.0.0" to 3
            )
            for ((addr, mask) in subnets) {
                try { builder.addRoute(addr, mask) } catch (ex: Exception) {}
            }
        }
        
        // Intercept common DNS IPs to prevent leaks
        val dnsToHijack = listOf(
            "1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9", 
            "149.112.112.112", "208.67.222.222", "208.67.220.220",
            "112.215.198.248", "112.215.198.249" // Common ISP DNS (XL/Tsel)
        )
        for (dns in dnsToHijack) {
            try { builder.addRoute(dns, 32) } catch (e: Exception) {}
        }

        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {}

        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")
        builder.addAddress("172.19.0.1", 30)

        try {
            vpnInterface = builder.establish()
            val fd = vpnInterface?.fd ?: return

            Log.i("ZIVPN-Tun", "VPN Interface established. FD: $fd")

            // 3. Start tun2socks (Go/gVisor Engine) via JNI
            Thread {
                try {
                    val udpTimeout = 60000L
                    val finalMtu = 1500L // Set MTU to 1500 as requested
                    logToApp("Starting Engine with MTU $finalMtu...")
                    mobile.Mobile.setLogHandler(tunLogger)
                    mobile.Mobile.start(
                        "socks5://127.0.0.1:7777",
                        "fd://$fd",
                        "info",
                        finalMtu,
                        udpTimeout,
                        "4m", 
                        "4m", 
                        true    // Re-enable auto-tuning for 1500 MTU stability
                    )
                    logToApp("Tun2Socks Engine Started successfully.")
                } catch (e: Exception) {
                    logToApp("Engine Error: ${e.message}")
                }
            }.start()

            prefs.edit().putBoolean("flutter.vpn_running", true).apply()

        } catch (e: Throwable) {
            Log.e("ZIVPN-Tun", "Error starting VPN: ${e.message}")
            stopSelf()
        }
    }

    private fun startCores(ip: String, range: String, pass: String, obfs: String, multiplier: Double) {
        val libDir = applicationInfo.nativeLibraryDir
        val libUz = File(libDir, "libuz.so").absolutePath
        val libLoad = File(libDir, "libload.so").absolutePath
        
        val baseConn = 131072
        val baseWin = 327680
        val dynamicConn = (baseConn * multiplier).toInt()
        val dynamicWin = (baseWin * multiplier).toInt()
        
        val ports = listOf(20080, 20081, 20082, 20083)
        val tunnelTargets = mutableListOf<String>()

        for (port in ports) {
            val hyConfig = JSONObject()
            hyConfig.put("server", "$ip:$range")
            hyConfig.put("obfs", obfs)
            hyConfig.put("auth", pass)
            
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
        
        try {
            mobile.Mobile.stop()
        } catch (e: Exception) {
            Log.e("ZIVPN-Tun", "Error stopping Mobile engine: ${e.message}")
        }

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

        try {
            val cleanupCmd = arrayOf("sh", "-c", "pkill -9 libuz; pkill -9 libload; pkill -9 libuz.so; pkill -9 libload.so")
            Runtime.getRuntime().exec(cleanupCmd).waitFor()
        } catch (e: Exception) {}

        vpnInterface?.close()
        vpnInterface = null
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        prefs.edit().putBoolean("flutter.vpn_running", false).apply()
        
        stopSelf()
    }

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }
}
