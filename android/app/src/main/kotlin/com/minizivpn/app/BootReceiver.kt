package com.minizivpn.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val autoStart = prefs.getBoolean("flutter.auto_start_vpn", false)
        if (!autoStart) return

        val startIntent = Intent(context, ZivpnService::class.java).apply {
            action = ZivpnService.ACTION_CONNECT
        }
        ContextCompat.startForegroundService(context, startIntent)
    }
}
