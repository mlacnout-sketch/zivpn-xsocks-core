package com.minizivpn.app

import java.net.InetAddress
import kotlin.math.pow

object RoutingUtils {

    /**
     * Menghasilkan daftar subnet CIDR minimal yang menutupi seluruh IPv4 kecuali satu IP spesifik.
     * Algoritma ini dioptimalkan untuk latensi rendah dan throughput tinggi pada VpnService.
     */
    fun calculateDynamicRoutes(excludeIp: String): List<Pair<String, Int>> {
        val routes = mutableListOf<Pair<String, Int>>()
        try {
            val ipLong = bytesToLong(InetAddress.getByName(excludeIp).address)
            
            var current = 0L
            val maxIp = 0xFFFFFFFFL
            
            while (current <= maxIp) {
                if (current == ipLong) {
                    current++
                    if (current > maxIp) break
                    continue
                }
                
                // Cari mask terbesar yang tidak mencakup excludeIp
                var mask = 32
                while (mask > 0) {
                    val nextMask = mask - 1
                    val size = 1L shl (32 - nextMask)
                    val maskValue = (0xFFFFFFFFL shl (32 - nextMask)) and 0xFFFFFFFFL
                    val network = current and maskValue
                    
                    // Cek jika blok ini mencakup excludeIp atau melampaui rentang
                    if (excludeIpInBlock(network, size, ipLong) || (current + size - 1) > maxIp || current != network) {
                        break
                    }
                    mask = nextMask
                }
                
                routes.add(longToIp(current) to mask)
                current += 1L shl (32 - mask)
                if (current == 0L) break // Overflow check
            }
        } catch (e: Exception) {
            return listOf("0.0.0.0" to 1, "128.0.0.0" to 1)
        }
        
        if (routes.isEmpty()) {
            routes.add("0.0.0.0" to 0)
        }
        
        return routes
    }

    private fun excludeIpInBlock(network: Long, size: Long, exclude: Long): Boolean {
        return exclude >= network && exclude < (network + size)
    }

    private fun bytesToLong(bytes: ByteArray): Long {
        var result = 0L
        for (i in 0 until 4) {
            result = result shl 8 or (bytes[i].toLong() and 0xff)
        }
        return result
    }

    private fun longToIp(ip: Long): String {
        return "${(ip shr 24) and 0xff}.${(ip shr 16) and 0xff}.${(ip shr 8) and 0xff}.${ip and 0xff}"
    }

    /**
     * Melakukan uji resolusi DNS secara asinkron untuk memantau kesehatan koneksi.
     */
    suspend fun performDnsHealthCheck(domain: String = "google.com"): Boolean {
        return try {
            val start = System.currentTimeMillis()
            val address = InetAddress.getByName(domain)
            // Log latency if needed: System.currentTimeMillis() - start
            address.hostAddress != null
        } catch (e: Exception) {
            false
        }
    }
}
