package com.minizivpn.app

import android.content.Context
import java.io.File

object Pdnsd {
    private const val DEFAULT_UPSTREAM_DNS_IP = "208.67.222.222"
    private const val DEFAULT_UPSTREAM_DNS_PORT = "53"

    fun getExecutable(context: Context): String {
        return File(context.applicationInfo.nativeLibraryDir, "libpdnsd.so").absolutePath
    }

    private fun parseUpstreamDns(upstreamDns: String): Pair<String, String> {
        val value = upstreamDns.trim()
        if (value.isEmpty()) {
            return DEFAULT_UPSTREAM_DNS_IP to DEFAULT_UPSTREAM_DNS_PORT
        }

        // IPv6 format: [ip]:port
        if (value.startsWith("[") && value.contains("]")) {
            val endBracket = value.indexOf(']')
            val ip = value.substring(1, endBracket).ifEmpty { DEFAULT_UPSTREAM_DNS_IP }
            val port = value.substring(endBracket + 1).removePrefix(":").ifEmpty { DEFAULT_UPSTREAM_DNS_PORT }
            return ip to port
        }

        // IPv4/hostname with optional :port
        val lastColon = value.lastIndexOf(':')
        if (lastColon > 0 && value.indexOf(':') == lastColon) {
            val ip = value.substring(0, lastColon).ifEmpty { DEFAULT_UPSTREAM_DNS_IP }
            val port = value.substring(lastColon + 1).ifEmpty { DEFAULT_UPSTREAM_DNS_PORT }
            return ip to port
        }

        return value to DEFAULT_UPSTREAM_DNS_PORT
    }

    fun writeConfig(context: Context, listenPort: Int, upstreamDns: String): String {
        val cacheDir = File(context.filesDir, "pdnsd_cache")
        if (!cacheDir.exists()) cacheDir.mkdirs()
        
        val configFile = File(context.filesDir, "pdnsd.conf")
        
        val (ip, port) = parseUpstreamDns(upstreamDns)
        
        val conf = """
            global {
                perm_cache=2048;
                cache_dir="${cacheDir.absolutePath}";
                server_ip = 169.254.1.1;
                server_port = $listenPort;
                status_ctl = on;
                query_method=tcp_only; 
                min_ttl=15m;
                max_ttl=1w;
                timeout=10;
                daemon=off;
                verbosity=2;
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
