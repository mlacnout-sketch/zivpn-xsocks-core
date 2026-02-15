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

object Pdnsd {
    private const val DEFAULT_DNS_PORT = 53
    private const val DEFAULT_UPSTREAM_DNS = "1.1.1.1,1.0.0.1"

    private data class UpstreamEndpoint(
        val host: String,
        val port: Int
    )

    private data class UpstreamDnsConfig(
        val serverBlocks: String
    )

    fun getExecutable(context: Context): String {
        return File(context.applicationInfo.nativeLibraryDir, "libpdnsd.so").absolutePath
    }

    private fun parsePort(rawPort: String?): Int? {
        val p = rawPort?.trim()?.toIntOrNull() ?: return null
        return if (p in 1..65535) p else null
    }

    private fun autoDetectPort(host: String): Int {
        // Default DNS port; can be overridden per endpoint with host:port.
        return DEFAULT_DNS_PORT
    }

    private fun parseEndpoint(rawEndpoint: String): UpstreamEndpoint? {
        val endpoint = rawEndpoint.trim()
        if (endpoint.isEmpty()) return null

        if (endpoint.startsWith("[") && endpoint.contains("]")) {
            val close = endpoint.indexOf(']')
            if (close <= 1) return null

            val host = endpoint.substring(1, close)
            if (host.isBlank()) return null

            val explicitPort = if (close + 1 < endpoint.length && endpoint[close + 1] == ':') {
                parsePort(endpoint.substring(close + 2))
            } else {
                null
            }
            return UpstreamEndpoint(host = host, port = explicitPort ?: autoDetectPort(host))
        }

        val colonCount = endpoint.count { it == ':' }
        return when {
            colonCount == 0 -> UpstreamEndpoint(host = endpoint, port = autoDetectPort(endpoint))
            colonCount == 1 -> {
                val parts = endpoint.split(':', limit = 2)
                val host = parts[0].trim()
                if (host.isBlank()) return null
                UpstreamEndpoint(host = host, port = parsePort(parts[1]) ?: autoDetectPort(host))
            }
            else -> UpstreamEndpoint(host = endpoint, port = autoDetectPort(endpoint))
        }
    }

    private fun parseUpstreamDns(raw: String): UpstreamDnsConfig {
        val source = if (raw.isBlank()) DEFAULT_UPSTREAM_DNS else raw
        val parsedEndpoints = source.split(',').mapNotNull { parseEndpoint(it) }

        val endpoints = if (parsedEndpoints.isEmpty()) {
            listOf(
                UpstreamEndpoint("1.1.1.1", DEFAULT_DNS_PORT),
                UpstreamEndpoint("1.0.0.1", DEFAULT_DNS_PORT)
            )
        } else {
            parsedEndpoints
        }

        val groupedByPort = linkedMapOf<Int, MutableList<String>>()
        endpoints.forEach { endpoint ->
            groupedByPort.getOrPut(endpoint.port) { mutableListOf() }.add(endpoint.host)
        }

        val blocks = groupedByPort.entries.mapIndexed { idx, entry ->
            val label = if (groupedByPort.size == 1) "upstream" else "upstream_${idx + 1}"
            """
            server {
                label= "$label";
                ip = ${entry.value.joinToString(", ")};
                port = ${entry.key};
                uptest = none;
                proxy_only=on;
            }
            """.trimIndent()
        }

        return UpstreamDnsConfig(serverBlocks = blocks.joinToString("\n\n"))
    }

    fun writeConfig(context: Context, listenPort: Int, upstreamDns: String, tuning: PdnsdTuning): String {
        val cacheDir = File(context.filesDir, "pdnsd_cache")
        if (!cacheDir.exists()) cacheDir.mkdirs()

        val configFile = File(context.filesDir, "pdnsd.conf")
        val upstreamConfig = parseUpstreamDns(upstreamDns)

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

            ${upstreamConfig.serverBlocks}

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
