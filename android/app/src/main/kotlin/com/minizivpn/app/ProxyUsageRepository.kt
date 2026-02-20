package com.minizivpn.app

import android.content.Context

class ProxyUsageRepository(context: Context) {
    private val prefs = context.getSharedPreferences("proxy_usage_stats", Context.MODE_PRIVATE)

    fun getTotalBytes(proxyId: String): Long {
        return prefs.getLong("usage_total_$proxyId", 0L)
    }

    fun addToTotal(proxyId: String, deltaBytes: Long) {
        if (deltaBytes <= 0) return
        val current = getTotalBytes(proxyId)
        prefs.edit().putLong("usage_total_$proxyId", current + deltaBytes).apply()
    }

    fun saveSession(proxyId: String, startTx: Long, startRx: Long, lastPersistedDelta: Long = 0L) {
        prefs.edit()
            .putString("session_proxy_id", proxyId)
            .putLong("session_start_tx", startTx)
            .putLong("session_start_rx", startRx)
            .putLong("session_last_persisted_delta", lastPersistedDelta)
            .apply()
    }

    fun loadSession(): ProxyUsageSession? {
        val proxyId = prefs.getString("session_proxy_id", null) ?: return null
        val startTx = prefs.getLong("session_start_tx", -1L)
        val startRx = prefs.getLong("session_start_rx", -1L)
        val lastPersistedDelta = prefs.getLong("session_last_persisted_delta", 0L)
        if (startTx < 0 || startRx < 0) return null
        return ProxyUsageSession(proxyId, startTx, startRx, lastPersistedDelta)
    }

    fun updateLastPersistedDelta(delta: Long) {
        prefs.edit().putLong("session_last_persisted_delta", delta).apply()
    }

    fun clearSession() {
        prefs.edit()
            .remove("session_proxy_id")
            .remove("session_start_tx")
            .remove("session_start_rx")
            .remove("session_last_persisted_delta")
            .apply()
    }
}

data class ProxyUsageSession(
    val proxyId: String,
    val startTx: Long,
    val startRx: Long,
    val lastPersistedDelta: Long,
)
