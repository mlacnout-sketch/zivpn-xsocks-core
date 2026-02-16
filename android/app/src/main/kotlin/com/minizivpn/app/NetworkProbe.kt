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

    fun getSmartConfig(): Map<String, Int> {
        val score = getNetworkScore()
        
        val recvWin: Int
        val recvConn: Int
        
        // Strict Thresholds
        if (score >= 85) {
            // Excellent Condition (High Band + Clean Signal) -> Throughput Mode
            recvWin = 655360
            recvConn = 262144
        } else if (score >= 55) {
            // Good Condition -> Balanced Mode
            recvWin = 327680
            recvConn = 131072
        } else {
            // Poor/Congested/Noisy -> Latency Mode (Anti-Bufferbloat)
            recvWin = 163840
            recvConn = 65536
        }
        
        return mapOf(
            "score" to score,
            "recv_win" to recvWin,
            "recv_conn" to recvConn
        )
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
