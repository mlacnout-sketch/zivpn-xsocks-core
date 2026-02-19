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
    fun getExecutable(context: Context): String {
        return File(context.applicationInfo.nativeLibraryDir, "libpdnsd.so").absolutePath
    }

    fun writeConfig(context: Context, listenPort: Int, upstreamDns: String, tuning: PdnsdTuning): String {
        val cacheDir = File(context.filesDir, "pdnsd_cache")
        if (!cacheDir.exists()) cacheDir.mkdirs()

        val configFile = File(context.filesDir, "pdnsd.conf")

        // Handle IP or IP:PORT format. Default to 53 if no port specified.
        val parts = upstreamDns.split(":")
        val ip = parts[0].ifEmpty { "8.8.8.8" }
        val port = if (parts.size > 1) parts[1] else "53"

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
