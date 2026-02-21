package com.minizivpn.app

import android.content.Context
import java.io.File

data class PdnsdTuning(
    val permCache: Int = 2048,
    val timeout: Int = 10,
    val minTtl: String = "15m",
    val maxTtl: String = "1w",
    val queryMethod: String = "udp_tcp",
    val verbosity: Int = 2
)

object Pdnsd {
    private const val DEFAULT_DNS_IP = "8.8.8.8"
    private const val DEFAULT_DNS_PORT = "53"

    private fun parseDnsEndpoint(upstreamDns: String): Pair<String, String> {
        val trimmed = upstreamDns.trim()
        if (trimmed.isEmpty()) {
            return DEFAULT_DNS_IP to DEFAULT_DNS_PORT
        }

        if (trimmed.startsWith("[")) {
            val closingBracketIndex = trimmed.indexOf(']')
            if (closingBracketIndex > 1) {
                val host = trimmed.substring(1, closingBracketIndex)
                val explicitPort = trimmed.substring(closingBracketIndex + 1).removePrefix(":")
                val port = explicitPort.takeIf { it.toIntOrNull() in 1..65535 } ?: DEFAULT_DNS_PORT
                return host to port
            }
        }

        // Raw IPv6 literals contain multiple ':' and should not be split as host:port.
        if (trimmed.count { it == ':' } > 1) {
            return trimmed to DEFAULT_DNS_PORT
        }

        val parts = trimmed.split(':', limit = 2)
        val ip = parts[0].ifEmpty { DEFAULT_DNS_IP }
        val port = parts.getOrNull(1)?.takeIf { it.toIntOrNull() in 1..65535 } ?: DEFAULT_DNS_PORT
        return ip to port
    }

    fun getExecutable(context: Context): String {
        return File(context.applicationInfo.nativeLibraryDir, "libpdnsd.so").absolutePath
    }

    fun writeConfig(context: Context, listenPort: Int, upstreamDns: String, tuning: PdnsdTuning): String {
        val cacheDir = File(context.filesDir, "pdnsd_cache")
        if (!cacheDir.exists()) cacheDir.mkdirs()

        val configFile = File(context.filesDir, "pdnsd.conf")

        // Handle IPv4, hostnames, [IPv6]:PORT and raw IPv6 literals.
        val (ip, port) = parseDnsEndpoint(upstreamDns)

        val conf = """
            global {
                perm_cache=${tuning.permCache};
                cache_dir="${cacheDir.absolutePath}";
                server_ip = 169.254.1.1;
                server_port = $listenPort;
                status_ctl = on;
                query_method=${tuning.queryMethod};
                min_ttl=${tuning.minTtl};
                max_ttl=${tuning.maxTtl};
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
