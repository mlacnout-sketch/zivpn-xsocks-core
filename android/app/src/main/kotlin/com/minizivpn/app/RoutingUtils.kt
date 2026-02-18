package com.minizivpn.app

import java.net.InetAddress
import kotlin.math.pow

object RoutingUtils {

    /**
     * Menghasilkan daftar subnet yang menutupi seluruh IPv4 kecuali satu IP spesifik.
     * Ini memastikan traffic ke server proxy tidak masuk ke tunnel.
     */
    fun calculateDynamicRoutes(excludeIp: String): List<Pair<String, Int>> {
        val routes = mutableListOf<Pair<String, Int>>()

        try {
            val ipAddr = InetAddress.getByName(excludeIp)
            val ipBytes = ipAddr.address

            // Routing table yang dibangun di service ini adalah IPv4-only.
            // Jika resolve menghasilkan IPv6 (contoh DNS64 64:ff9b::/96),
            // jangan dipaksa masuk kalkulasi IPv4 karena hasilnya salah.
            if (ipBytes.size != 4) {
                return defaultSplitRoutes()
            }

            val ipLong = bytesToLong(ipBytes)
            fillRoutes(0, 4294967295L, ipLong, routes)
        } catch (e: Exception) {
            return defaultSplitRoutes()
        }

        return routes
    }

    private fun defaultSplitRoutes(): List<Pair<String, Int>> {
        return listOf("0.0.0.0" to 1, "128.0.0.0" to 1)
    }

    private fun fillRoutes(start: Long, end: Long, exclude: Long, routes: MutableList<Pair<String, Int>>) {
        if (exclude < start || exclude > end) {
            // Range ini tidak mengandung IP yang dikecualikan, tambahkan sebagai blok tunggal
            addRangeAsCidrs(start, end, routes)
            return
        }
        if (start == end) return // Ini adalah IP yang dikecualikan

        // Bagi range menjadi dua dan rekursif
        val mid = start + (end - start) / 2
        fillRoutes(start, mid, exclude, routes)
        fillRoutes(mid + 1, end, exclude, routes)
    }

    private fun addRangeAsCidrs(start: Long, end: Long, routes: MutableList<Pair<String, Int>>) {
        var s = start
        while (s <= end) {
            var maxLen = 32
            while (maxLen > 0) {
                val size = 2.0.pow(32 - maxLen + 1).toLong()
                val nextMask = maxLen - 1
                val maskSize = 2.0.pow(32 - nextMask).toLong()
                if (s % maskSize == 0L && s + maskSize - 1 <= end) {
                    maxLen = nextMask
                } else {
                    break
                }
            }
            val size = 2.0.pow(32 - maxLen).toLong()
            routes.add(longToIp(s) to maxLen)
            s += size
            if (s == 0L) break // overflow
        }
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
}
