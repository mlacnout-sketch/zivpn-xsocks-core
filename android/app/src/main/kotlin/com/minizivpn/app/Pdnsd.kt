package com.minizivpn.app

import android.content.Context
import java.io.File

data class PdnsdTuning(
    val permCache: Int = 2048,
    val timeout: Int = 10,
    val minTtl: String = "15m",
    val maxTtl: String = "1w",
    val queryMethod: String = "tcp_only",
    val verbosity: Int = 2
)

private fun sanitizeTtl(value: String, fallback: String): String {
    val raw = value.trim().lowercase()
    val ttlRegex = Regex("^\\d+[smhdw]$")
    return if (ttlRegex.matches(raw)) raw else fallback
}

private fun parseUpstream(upstreamDns: String): Pair<String, String> {
    val input = upstreamDns.trim()
    if (input.isEmpty()) return "1.1.1.1" to "53"

    val host: String
    val portRaw: String?

    if (input.startsWith("[") && input.contains("]")) {
        // Bracketed IPv6 format: [addr]:port
        val end = input.indexOf("]")
        host = input.substring(1, end).trim()
        portRaw = input.substring(end + 1).trim().removePrefix(":").ifEmpty { null }
    } else {
        val colonCount = input.count { it == ':' }
        if (colonCount == 1) {
            // hostname:port or ipv4:port
            host = input.substringBefore(":").trim()
            portRaw = input.substringAfter(":").trim().ifEmpty { null }
        } else {
            // hostname without port or raw IPv6 without brackets.
            host = input
            portRaw = null
        }
    }

    val sanitizedHost = host.ifEmpty { "1.1.1.1" }
    val port = portRaw?.toIntOrNull()?.coerceIn(1, 65535)?.toString() ?: "53"
    return sanitizedHost to port
}


object Pdnsd {
    fun getExecutable(context: Context): String {
        return File(context.applicationInfo.nativeLibraryDir, "libpdnsd.so").absolutePath
    }

    fun resolveSmartTuning(profile: String, score: Int, base: PdnsdTuning): PdnsdTuning {
        if (profile != "smart") return base

        return when {
            score >= 75 -> base.copy(
                permCache = 4096,
                timeout = 8,
                minTtl = "30m",
                maxTtl = "1w",
                queryMethod = "udp_tcp",
                verbosity = 1
            )
            score in 45..74 -> base.copy(
                permCache = 2048,
                timeout = 10,
                minTtl = "15m",
                maxTtl = "1w",
                queryMethod = "tcp_only",
                verbosity = 2
            )
            score in 0..44 -> base.copy(
                permCache = 1024,
                timeout = 5,
                minTtl = "5m",
                maxTtl = "12h",
                queryMethod = "tcp_only",
                verbosity = 1
            )
            else -> base
        }
    }

    fun writeConfig(context: Context, listenPort: Int, upstreamDns: String, tuning: PdnsdTuning): String {
        val cacheDir = File(context.filesDir, "pdnsd_cache")
        if (!cacheDir.exists()) cacheDir.mkdirs()

        val configFile = File(context.filesDir, "pdnsd.conf")

        val (ip, port) = parseUpstream(upstreamDns)
        val minTtl = sanitizeTtl(tuning.minTtl, "15m")
        val maxTtl = sanitizeTtl(tuning.maxTtl, "1w")

        val conf = """
            global {
                perm_cache=${tuning.permCache};
                cache_dir="${cacheDir.absolutePath}";
                server_ip = 169.254.1.1;
                server_port = $listenPort;
                status_ctl = on;
                query_method=${tuning.queryMethod};
                min_ttl=$minTtl;
                max_ttl=$maxTtl;
                timeout=${tuning.timeout};
                daemon=off;
                verbosity=${tuning.verbosity};
            }

            server {
                label= "upstream";
                ip = $ip;
                port = $port;
                uptest = none;
                proxy_only=on;
            }

            rr {
                name=localhost;
                reverse=on;
                a=127.0.0.1;
                owner=localhost;
                soa=localhost,root.localhost,42,86400,900,86400,86400;
            }
        """.trimIndent()

        configFile.writeText(conf)
        return configFile.absolutePath
    }
}
