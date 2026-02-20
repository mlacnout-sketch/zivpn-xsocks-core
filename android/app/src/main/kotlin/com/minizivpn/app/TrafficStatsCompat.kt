package com.minizivpn.app

import android.net.TrafficStats
import java.io.File

object TrafficStatsCompat {

    fun getReliableRxBytes(uid: Int): Long {
        val uidRx = TrafficStats.getUidRxBytes(uid)
        if (uidRx != TrafficStats.UNSUPPORTED.toLong() && uidRx >= 0L) return uidRx

        val totalRx = TrafficStats.getTotalRxBytes()
        if (totalRx != TrafficStats.UNSUPPORTED.toLong() && totalRx >= 0L) return totalRx

        return readProcNetDevTotals().first
    }

    fun getReliableTxBytes(uid: Int): Long {
        val uidTx = TrafficStats.getUidTxBytes(uid)
        if (uidTx != TrafficStats.UNSUPPORTED.toLong() && uidTx >= 0L) return uidTx

        val totalTx = TrafficStats.getTotalTxBytes()
        if (totalTx != TrafficStats.UNSUPPORTED.toLong() && totalTx >= 0L) return totalTx

        return readProcNetDevTotals().second
    }

    private fun readProcNetDevTotals(): Pair<Long, Long> {
        return try {
            var rxTotal = 0L
            var txTotal = 0L
            File("/proc/net/dev").useLines { lines ->
                lines.drop(2).forEach { line ->
                    val parts = line.split(":", limit = 2)
                    if (parts.size != 2) return@forEach

                    val iface = parts[0].trim()
                    if (iface == "lo") return@forEach

                    val fields = parts[1].trim().split(Regex("\\s+"))
                    if (fields.size < 16) return@forEach

                    val rx = fields[0].toLongOrNull() ?: 0L
                    val tx = fields[8].toLongOrNull() ?: 0L
                    rxTotal += rx
                    txTotal += tx
                }
            }
            Pair(rxTotal.coerceAtLeast(0L), txTotal.coerceAtLeast(0L))
        } catch (_: Exception) {
            Pair(0L, 0L)
        }
    }
}
