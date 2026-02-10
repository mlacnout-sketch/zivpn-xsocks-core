package com.minizivpn.app

import android.content.Context
import java.io.File

object Pdnsd {
    fun getExecutable(context: Context): String {
        // Android extracts native libs to nativeLibraryDir.
        // We renamed pdnsd executable to libpdnsd.so in CMake.
        return File(context.applicationInfo.nativeLibraryDir, "libpdnsd.so").absolutePath
    }

    fun writeConfig(context: Context, listenPort: Int, upstreamIp: String): String {
        val cacheDir = File(context.cacheDir, "pdnsd_cache")
        if (!cacheDir.exists()) cacheDir.mkdirs()
        
        val configFile = File(context.filesDir, "pdnsd.conf")
        
        // Configuration for non-root Android environment
        // We use tcp_only query method to avoid UDP loops if tun2socks intercepts UDP DNS
        val conf = """
            global {
                perm_cache=1024;
                cache_dir="${cacheDir.absolutePath}";
                server_ip = 127.0.0.1;
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
                ip = $upstreamIp;
                uptest = none;
                proxy_only=on;
            }
        """.trimIndent()
        
        configFile.writeText(conf)
        return configFile.absolutePath
    }
}
