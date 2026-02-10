package com.minizivpn.app

import android.content.Context
import java.io.File

object Pdnsd {
    fun getExecutable(context: Context): String {
        return File(context.applicationInfo.nativeLibraryDir, "libpdnsd.so").absolutePath
    }

    fun writeConfig(context: Context, listenPort: Int, upstreamDns: String): String {
        val cacheDir = File(context.filesDir, "pdnsd_cache")
        if (!cacheDir.exists()) cacheDir.mkdirs()
        
        val configFile = File(context.filesDir, "pdnsd.conf")
        
        // Handle IP or IP:PORT format. Default to 443 if no port specified.
        val parts = upstreamDns.split(":")
        val ip = parts[0].ifEmpty { "208.67.222.222" } // Default to OpenDNS
        val port = if (parts.size > 1) parts[1] else "443" 
        
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
