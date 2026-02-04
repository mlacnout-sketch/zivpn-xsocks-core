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

/**
 * ZIVPN TunService
 * Handles the VpnService interface and integrates with tun2socks via JNI.
 */
@Keep
class ZivpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "com.minizivpn.app.CONNECT"
        const val ACTION_DISCONNECT = "com.minizivpn.app.DISCONNECT"
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val processes = mutableListOf<Process>()

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
        
        // Advanced Routing (Bypassing Private Networks to prevent tcp4 errors)
        val subnets = listOf(
            "0.0.0.0" to 5,        // 0.0.0.0 - 7.255.255.255
            "8.0.0.0" to 7,        // 8.0.0.0 - 9.255.255.255
            "11.0.0.0" to 8,       // 11.0.0.0 - 11.255.255.255
            "12.0.0.0" to 6,       // 12.0.0.0 - 15.255.255.255
            "16.0.0.0" to 4,       // 16.0.0.0 - 31.255.255.255
            "32.0.0.0" to 3,       // 32.0.0.0 - 63.255.255.255
            "64.0.0.0" to 2,       // 64.0.0.0 - 127.255.255.255
            "128.0.0.0" to 3,      // 128.0.0.0 - 159.255.255.255
            "160.0.0.0" to 5,      // 160.0.0.0 - 167.255.255.255
            "168.0.0.0" to 6,      // 168.0.0.0 - 171.255.255.255
            "176.0.0.0" to 4,      // 176.0.0.0 - 191.255.255.255
            "192.0.0.0" to 9,      // 192.0.0.0 - 192.127.255.255
            "192.128.0.0" to 11,   // 192.128.0.0 - 192.159.255.255
            "192.160.0.0" to 13,   // 192.160.0.0 - 192.167.255.255
            "192.169.0.0" to 16,   // 192.169.0.0 - 192.169.255.255
            "192.170.0.0" to 15,   // 192.170.0.0 - 192.171.255.255
            "192.172.0.0" to 14,   // 192.172.0.0 - 192.175.255.255
            "193.0.0.0" to 8,      // 193.0.0.0 - 193.255.255.255
            "194.0.0.0" to 7,      // 194.0.0.0 - 195.255.255.255
            "196.0.0.0" to 6,      // 196.0.0.0 - 199.255.255.255
            "200.0.0.0" to 3       // 200.0.0.0 - 231.255.255.255
        )
        for ((addr, mask) in subnets) {
            try {
                builder.addRoute(addr, mask)
            } catch (e: Exception) {
                Log.e("ZIVPN-Tun", "Failed to add route: $addr/$mask")
            }
        }
        
        // Exclude server IP if it's a valid IP address to avoid loopback
        if (ip.matches(Regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$"))) {
            try {
                // In modern Android, we can try to exclude the route if API supports it
                // For now, adding a host route with a higher priority/different path is complex via VpnService.
                // The safest way is to ensure the server IP is NOT inside any of the 'subnets' above.
                // Our subnets already exclude most RFC1918, but if VPS is a public IP, 
                // it might be covered. However, addDisallowedApplication usually handles the UID of this app.
                Log.i("ZIVPN-Tun", "Server IP detected: $ip")
            } catch (e: Exception) {}
        }
        builder.addRoute("198.18.0.1", 32) // Capture FakeDNS traffic if needed

        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {}

        builder.addDnsServer("8.8.8.8")
        builder.addDnsServer("1.1.1.1")
        builder.addAddress("172.19.0.1", 30)

        // DNS Hijacking: Force these DNS IPs into the TUN interface
        builder.addRoute("8.8.8.8", 32)
        builder.addRoute("8.8.4.4", 32)
        builder.addRoute("1.1.1.1", 32)
        builder.addRoute("1.0.0.1", 32)

        try {
            vpnInterface = builder.establish()
            val fd = vpnInterface?.fd ?: return

            Log.i("ZIVPN-Tun", "VPN Interface established. FD: $fd")

            // 3. Start tun2socks (Go/gVisor Engine) via JNI
            Thread {
                try {
                    val udpTimeout = 60000L // 1 minute in ms
                    mobile.Mobile.start(
                        "socks5://127.0.0.1:7777",
                        "fd://$fd",
                        "info",
                        mtu.toLong(),
                        udpTimeout,
                        "2m",    // TCP Send Buffer
                        "2m",    // TCP Receive Buffer
                        false    // TCP Auto Tuning (Disabled)
                    )
                    Log.i("ZIVPN-Tun", "Tun2Socks Engine Started")
                } catch (e: Exception) {
                    Log.e("ZIVPN-Tun", "Failed to start Tun2Socks: ${e.message}")
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
            tunnelTargets.add("127.0.0.1:$port")
        }
        
        Thread.sleep(1000)

        val lbCmd = mutableListOf(libLoad, "-lport", "7777", "-tunnel")
        lbCmd.addAll(tunnelTargets)
        
        val lbPb = ProcessBuilder(lbCmd)
        lbPb.directory(filesDir)
        lbPb.environment()["LD_LIBRARY_PATH"] = libDir
        val lbProcess = lbPb.start()
        processes.add(lbProcess)
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
