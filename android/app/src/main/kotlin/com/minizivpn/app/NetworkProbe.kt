package com.minizivpn.app

import android.content.Context
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellSignalStrengthNr
import android.telephony.TelephonyManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import android.util.Log

class NetworkProbe(private val context: Context) {

    fun getSmartConfig(): Map<String, Any> {
        val score = getNetworkScore()
        
        // --- FLUID DYNAMIC TUNING ---
        // Instead of buckets, we use a linear mapping formula.
        // Every single point of score difference will result in a different window size.
        
        val minWin = 65536   // 64KB (Minimum safe)
        val maxWin = 1572864 // 1.5MB (Maximum safe for Android heap/buffer)
        
        // Calculate raw window based on score (0-100+)
        // Allow score to go slightly above 100 (bonus bands) for extra boost
        val effectiveScore = score.coerceIn(0, 120)
        
        // Linear Interpolation
        var rawWin = minWin + ((maxWin - minWin) * (effectiveScore / 100.0)).toInt()
        
        // STRICT GATE: If High Noise (SINR penalty was applied inside getNetworkScore),
        // we heavily dampen the window scaling to prevent bufferbloat.
        // The score calculation already handles this, but let's be safe.
        
        // Align to 4KB (4096 bytes) memory pages for kernel efficiency
        rawWin = (rawWin / 4096) * 4096
        
        val recvWin = rawWin
        // Connection window is typically 1/3 to 1/2 of receive window
        val recvConn = (recvWin / 2.5).toInt()

        // Apply score to all tunable native parameters so "smart" really drives
        // the complete stack, not only Hysteria receive windows.
        val tcpWnd = lerpInt(32768, 65535, score)
        val tcpSndBuf = tcpWnd
        val socksBuf = align4k(lerpInt(65536, 262144, score))
        val udpgwMaxConn = lerpInt(256, 1024, score)
        val udpgwBufferSize = lerpInt(16, 64, score)
        val pdnsdCacheEntries = lerpInt(2048, 4096, score)
        val pdnsdTimeoutSec = lerpInt(5, 10, score)
        val udpgwMemoryBudgetKb = lerpInt(8192, 65536, score)

        // Smart remote port ranges around common defaults.
        val smartServerPortRange = buildSmartPortRange(13000, lerpInt(1800, 7000, score))
        val smartUdpgwPortRange = buildSmartPortRange(7300, lerpInt(40, 480, score))

        return mapOf(
            "score" to score,
            "recv_win" to recvWin,
            "recv_conn" to recvConn,
            "tcp_wnd" to tcpWnd,
            "tcp_snd_buf" to tcpSndBuf,
            "socks_buf" to socksBuf,
            "udpgw_max_connections" to udpgwMaxConn,
            "udpgw_buffer_size" to udpgwBufferSize,
            "pdnsd_cache_entries" to pdnsdCacheEntries,
            "pdnsd_timeout_sec" to pdnsdTimeoutSec,
            "udpgw_memory_budget_kb" to udpgwMemoryBudgetKb,
            "smart_port_range" to smartServerPortRange,
            "udpgw_smart_port_range" to smartUdpgwPortRange
        )
    }

    private fun lerpInt(min: Int, max: Int, score: Int): Int {
        val normalized = score.coerceIn(0, 100) / 100.0
        return (min + ((max - min) * normalized)).toInt()
    }

    private fun align4k(value: Int): Int {
        return (value / 4096) * 4096
    }

    private fun buildSmartPortRange(center: Int, span: Int): String {
        val start = (center - span).coerceAtLeast(1024)
        val end = (center + span).coerceAtMost(65535)
        return "$start-$end"
    }

    private fun getNetworkScore(): Int {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        
        if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            Log.e("NetworkProbe", "Missing Location Permission")
            return 50
        }

        try {
            val allCellInfo = tm.allCellInfo
            if (allCellInfo.isNullOrEmpty()) return 50

            val cell = allCellInfo.firstOrNull { it.isRegistered } ?: allCellInfo[0]

            var rsrp = -140
            var sinr = -20
            var earfcn = -1
            var type = "UNKNOWN"
            var bandLabel = "Unknown"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && cell is CellInfoNr) {
                type = "5G"
                val signal = cell.cellSignalStrength as CellSignalStrengthNr
                val identity = cell.cellIdentity as CellIdentityNr
                rsrp = signal.ssRsrp
                sinr = signal.ssSinr
                earfcn = identity.nrarfcn
                bandLabel = getBandFromNrarfcn(earfcn)
            } else if (cell is CellInfoLte) {
                type = "4G"
                val signal = cell.cellSignalStrength
                val identity = cell.cellIdentity
                rsrp = signal.rsrp
                sinr = signal.rssnr
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    earfcn = identity.earfcn
                }
                bandLabel = getBandFromEarfcn(earfcn)
            } else {
                return 60 // WiFi or Legacy
            }

            // --- STRICT LOGIC START ---

            // 1. Base Score from Signal Quality (SINR is King)
            // Normalized: -120 to -70 for RSRP, -5 to 25 for SINR
            val rsrpScore = normalize(rsrp, -120, -70)
            val sinrScore = normalize(sinr, -5, 25)
            
            // Weight: 70% SINR (Cleanliness), 30% RSRP (Strength)
            // A strong but noisy signal is useless for throughput.
            var rawScore = (rsrpScore * 0.3 + sinrScore * 0.7).toInt()

            // 2. Bandwidth/Capacity Bonus (The "NetMonster" Factor)
            val isHighBand = isHighCapacityBand(bandLabel)
            val isLowBand = isLowCapacityBand(bandLabel)

            if (isHighBand) {
                rawScore += 15 // Bonus for likely wider bandwidth (e.g. B40/B41)
            } else if (isLowBand) {
                rawScore -= 15 // Penalty for likely narrow bandwidth/congestion (e.g. B5/B8)
            }

            // 3. Strict Gates (Veto Power)
            
            // Gate A: Terrible Noise. If SINR < 3dB, force Low Score.
            if (sinr < 3) {
                rawScore = rawScore.coerceAtMost(40) // Force Latency Mode
                Log.d("NetworkProbe", "Gate: High Noise Detected (SINR $sinr). Forcing conservative mode.")
            }

            // Gate B: Weak Signal. If RSRP < -115, force Low Score.
            if (rsrp < -115) {
                rawScore = rawScore.coerceAtMost(45)
                Log.d("NetworkProbe", "Gate: Weak Signal (RSRP $rsrp). Forcing conservative mode.")
            }

            val finalScore = rawScore.coerceIn(0, 100)
            
            Log.d("NetworkProbe", "Net: $type | Band: $bandLabel ($earfcn) | RSRP: $rsrp | SINR: $sinr | Score: $finalScore")
            return finalScore

        } catch (e: Exception) {
            Log.e("NetworkProbe", "Error: ${e.message}")
            return 50
        }
    }

    private fun normalize(value: Int, min: Int, max: Int): Int {
        if (value >= max) return 100
        if (value <= min) return 0
        return ((value - min).toDouble() / (max - min) * 100).toInt()
    }

    private fun isHighCapacityBand(band: String): Boolean {
        // High bands usually have 20MHz+ bandwidth or TDD capacity
        // B1(2100), B3(1800), B7(2600), B40(2300), B41(2500), n78(3500)
        return band.contains("B1") || band.contains("B3") || band.contains("B7") || 
               band.contains("B40") || band.contains("B41") || band.contains("n78") || band.contains("n40")
    }

    private fun isLowCapacityBand(band: String): Boolean {
        // Low bands usually have 5-10MHz and high congestion/penetration
        // B5(850), B8(900), B20(800), B28(700)
        return band.contains("B5") || band.contains("B8") || band.contains("B20") || band.contains("B28")
    }

    private fun getBandFromEarfcn(earfcn: Int): String {
        if (earfcn == -1) return "Unknown"
        // Simplified Map for Common Asian/Global Bands
        return when (earfcn) {
            in 0..599 -> "B1 (2100)"
            in 1200..1949 -> "B3 (1800)"
            in 2400..2649 -> "B5 (850)"
            in 2750..3449 -> "B7 (2600)"
            in 3450..3799 -> "B8 (900)"
            in 6150..6449 -> "B20 (800)"
            in 9210..9659 -> "B28 (700)"
            in 38650..39649 -> "B40 (2300)"
            in 39650..41589 -> "B41 (2500)"
            else -> "Unknown ($earfcn)"
        }
    }

    private fun getBandFromNrarfcn(nrarfcn: Int): String {
        if (nrarfcn == -1) return "Unknown"
        // Rough 5G bands
        return when (nrarfcn) {
            in 620000..653333 -> "n78 (3500)"
            in 158200..164200 -> "n28 (700)"
            in 524000..538000 -> "n41 (2500)"
            in 460000..480000 -> "n40 (2300)"
            in 422000..434000 -> "n1 (2100)"
            in 361000..376000 -> "n3 (1800)"
            else -> "NR ($nrarfcn)"
        }
    }
}
