package com.minizivpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class KeepAliveService : Service() {

    private var currentMode: NotificationMode = NotificationMode.JET

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()

        val requestedMode = intent?.getStringExtra(EXTRA_NOTIFICATION_MODE)
        currentMode = NotificationMode.fromWireValue(requestedMode)

        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        val notification = buildNotification(pendingIntent)

        // ID 1002 for the keep-alive notification (to avoid conflict with VPN ID 1 or Ping ID 1001)
        startForeground(1002, notification)

        return START_STICKY
    }

    private fun buildNotification(pendingIntent: PendingIntent): Notification {
        val title = when (currentMode) {
            NotificationMode.FLIGHT -> "Mode Pesawat Aktif"
            NotificationMode.JET -> "AutoPilot Aktif"
        }

        val content = when (currentMode) {
            NotificationMode.FLIGHT -> "Sedang recovery jaringan: pesawat sedang terbang."
            NotificationMode.JET -> "Koneksi stabil: AutoPilot siap menjaga koneksimu."
        }

        val smallIcon = when (currentMode) {
            NotificationMode.FLIGHT -> R.drawable.ic_notification_plane
            NotificationMode.JET -> R.drawable.ic_notification_jet
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(smallIcon)
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "AutoPilot Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    companion object {
        const val CHANNEL_ID = "AutoPilotWatchdogChannel"
        const val EXTRA_NOTIFICATION_MODE = "notification_mode"
    }

    private enum class NotificationMode(val wireValue: String) {
        FLIGHT("flight"),
        JET("jet");

        companion object {
            fun fromWireValue(value: String?): NotificationMode {
                return values().firstOrNull { it.wireValue == value } ?: JET
            }
        }
    }
}
