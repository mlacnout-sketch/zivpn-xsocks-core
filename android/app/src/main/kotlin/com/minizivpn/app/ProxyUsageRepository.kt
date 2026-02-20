package com.minizivpn.app

import android.content.Context

class ProxyUsageRepository(context: Context) {
    private val prefs = context.getSharedPreferences("proxy_usage_stats", Context.MODE_PRIVATE)

    fun getTotalBytes(proxyId: String): Long {
        return getTotalTxBytes(proxyId) + getTotalRxBytes(proxyId)
    }

    fun getTotalTxBytes(proxyId: String): Long {
        return prefs.getLong("usage_total_tx_$proxyId", 0L)
    }

    fun getTotalRxBytes(proxyId: String): Long {
        return prefs.getLong("usage_total_rx_$proxyId", 0L)
    }

    fun addToTotal(proxyId: String, deltaTxBytes: Long, deltaRxBytes: Long) {
        if (deltaTxBytes <= 0 && deltaRxBytes <= 0) return
        val currentTx = getTotalTxBytes(proxyId)
        val currentRx = getTotalRxBytes(proxyId)
        prefs.edit()
            .putLong("usage_total_tx_$proxyId", currentTx + deltaTxBytes.coerceAtLeast(0L))
            .putLong("usage_total_rx_$proxyId", currentRx + deltaRxBytes.coerceAtLeast(0L))
            .apply()
    }

    fun saveSession(proxyId: String, startTx: Long, startRx: Long, lastPersistedTxDelta: Long = 0L, lastPersistedRxDelta: Long = 0L) {
        prefs.edit()
            .putString("session_proxy_id", proxyId)
            .putLong("session_start_tx", startTx)
            .putLong("session_start_rx", startRx)
            .putLong("session_last_persisted_tx_delta", lastPersistedTxDelta)
            .putLong("session_last_persisted_rx_delta", lastPersistedRxDelta)
            .apply()
    }

    fun loadSession(): ProxyUsageSession? {
        val proxyId = prefs.getString("session_proxy_id", null) ?: return null
        val startTx = prefs.getLong("session_start_tx", -1L)
        val startRx = prefs.getLong("session_start_rx", -1L)
        val lastPersistedTxDelta = prefs.getLong("session_last_persisted_tx_delta", 0L)
        val lastPersistedRxDelta = prefs.getLong("session_last_persisted_rx_delta", 0L)
        if (startTx < 0 || startRx < 0) return null
        return ProxyUsageSession(proxyId, startTx, startRx, lastPersistedTxDelta, lastPersistedRxDelta)
    }

    fun updateLastPersistedDelta(txDelta: Long, rxDelta: Long) {
        prefs.edit()
            .putLong("session_last_persisted_tx_delta", txDelta)
            .putLong("session_last_persisted_rx_delta", rxDelta)
            .apply()
    }

    fun clearSession() {
        prefs.edit()
            .remove("session_proxy_id")
            .remove("session_start_tx")
            .remove("session_start_rx")
            .remove("session_last_persisted_tx_delta")
            .remove("session_last_persisted_rx_delta")
            .apply()
    }
}

data class ProxyUsageSession(
    val proxyId: String,
    val startTx: Long,
    val startRx: Long,
    val lastPersistedTxDelta: Long,
    val lastPersistedRxDelta: Long,
)
