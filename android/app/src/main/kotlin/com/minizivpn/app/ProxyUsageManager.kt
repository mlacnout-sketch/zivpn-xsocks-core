package com.minizivpn.app

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.net.TrafficStats
import android.os.Build
import android.provider.Settings
import android.text.format.Formatter

class ProxyUsageManager(private val context: Context) {
    private val repository = ProxyUsageRepository(context)
    private val networkStatsManager =
        context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager

    fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun buildUsageStatsSettingsIntent(): Intent {
        return Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    fun startConnection(proxyId: String, uid: Int = android.os.Process.myUid()): Boolean {
        if (!hasUsageStatsPermission()) return false
        val totals = queryUidTotals(uid)
        repository.saveSession(proxyId, totals.first, totals.second)
        return true
    }

    fun computeCurrentDelta(proxyId: String? = null, uid: Int = android.os.Process.myUid()): Long {
        val snapshot = computeDeltaSnapshot(proxyId, uid) ?: return 0L
        return snapshot.totalDelta
    }

    fun computeDeltaSnapshot(proxyId: String? = null, uid: Int = android.os.Process.myUid()): ProxyUsageDeltaSnapshot? {
        val session = repository.loadSession() ?: return null
        if (proxyId != null && session.proxyId != proxyId) return null

        val totals = queryUidTotals(uid)
        val txDelta = (totals.first - session.startTx).coerceAtLeast(0L)
        val rxDelta = (totals.second - session.startRx).coerceAtLeast(0L)

        return ProxyUsageDeltaSnapshot(
            proxyId = session.proxyId,
            txDelta = txDelta,
            rxDelta = rxDelta,
            totalDelta = txDelta + rxDelta,
            lastPersistedTxDelta = session.lastPersistedTxDelta,
            lastPersistedRxDelta = session.lastPersistedRxDelta,
        )
    }

    fun commitDelta(proxyId: String? = null, uid: Int = android.os.Process.myUid()): Long {
        val snapshot = computeDeltaSnapshot(proxyId, uid) ?: return 0L

        val txIncrement = (snapshot.txDelta - snapshot.lastPersistedTxDelta).coerceAtLeast(0L)
        val rxIncrement = (snapshot.rxDelta - snapshot.lastPersistedRxDelta).coerceAtLeast(0L)

        if (txIncrement > 0L || rxIncrement > 0L) {
            repository.addToTotal(snapshot.proxyId, txIncrement, rxIncrement)
            repository.updateLastPersistedDelta(snapshot.txDelta, snapshot.rxDelta)
        }

        return repository.getTotalBytes(snapshot.proxyId)
    }

    fun getTotalBytes(proxyId: String): Long = repository.getTotalBytes(proxyId)

    fun getSessionAwareTotalBytes(proxyId: String, uid: Int = android.os.Process.myUid()): Long {
        val base = repository.getTotalBytes(proxyId)
        val snapshot = computeDeltaSnapshot(proxyId, uid) ?: return base
        val pendingTx = (snapshot.txDelta - snapshot.lastPersistedTxDelta).coerceAtLeast(0L)
        val pendingRx = (snapshot.rxDelta - snapshot.lastPersistedRxDelta).coerceAtLeast(0L)
        return base + pendingTx + pendingRx
    }

    fun getActiveProxyId(): String? = repository.loadSession()?.proxyId

    fun clearActiveSession() = repository.clearSession()

    fun formatBytes(bytes: Long): String = Formatter.formatFileSize(context, bytes)

    private fun queryUidTotals(uid: Int): Pair<Long, Long> {
        val endTime = System.currentTimeMillis()
        val startTime = 0L

        val mobile = queryDetails(ConnectivityManager.TYPE_MOBILE, uid, startTime, endTime)
        val wifi = queryDetails(ConnectivityManager.TYPE_WIFI, uid, startTime, endTime)

        val txTotal = mobile.first + wifi.first
        val rxTotal = mobile.second + wifi.second

        // Some ROMs / devices return empty NetworkStats buckets intermittently.
        // Fallback to TrafficStats to avoid flat zero realtime/session metrics.
        if (txTotal == 0L && rxTotal == 0L) {
            val txFallback = TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L)
            val rxFallback = TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L)
            if (txFallback > 0L || rxFallback > 0L) {
                return Pair(txFallback, rxFallback)
            }
        }

        return Pair(txTotal, rxTotal)
    }

    private fun queryDetails(networkType: Int, uid: Int, startTime: Long, endTime: Long): Pair<Long, Long> {
        var rx = 0L
        var tx = 0L

        try {
            val stats = networkStatsManager.queryDetailsForUid(networkType, null, startTime, endTime, uid)
            val bucket = NetworkStats.Bucket()
            while (stats.hasNextBucket()) {
                stats.getNextBucket(bucket)
                rx += bucket.rxBytes
                tx += bucket.txBytes
            }
            stats.close()
        } catch (_: Exception) {
            // Return partial totals; caller handles fallback behavior if needed.
        }

        return Pair(tx, rx)
    }
}


data class ProxyUsageDeltaSnapshot(
    val proxyId: String,
    val txDelta: Long,
    val rxDelta: Long,
    val totalDelta: Long,
    val lastPersistedTxDelta: Long,
    val lastPersistedRxDelta: Long,
)
