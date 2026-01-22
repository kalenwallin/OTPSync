package com.bunty.clipsync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat

class NotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_CLIPBOARD = "clipboard_channel"
        const val CHANNEL_SERVICE = "service_channel"
        const val NOTIFICATION_ID_CLIPBOARD = 1001
        const val NOTIFICATION_ID_SERVICE = 1002
    }

    init {
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val clipboardChannel = NotificationChannel(
                CHANNEL_CLIPBOARD,
                "Clipboard Sync",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for incoming clipboard content"
            }

            val serviceChannel = NotificationChannel(
                CHANNEL_SERVICE,
                "Sync Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent notification for background service"
            }

            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannels(listOf(clipboardChannel, serviceChannel))
        }
    }

    fun showClipboardNotification(content: String, isOtp: Boolean = false) {
        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        val title = if (isOtp) "OTP Detected" else "Clipboard Synced"
        val message = if (isOtp) content else "New content received from Mac"

        val builder = NotificationCompat.Builder(context, CHANNEL_CLIPBOARD)
            .setSmallIcon(R.mipmap.ic_launcher) // Ensure this icon exists or use a default
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
        
        // Add copy action if needed (Requires a BroadcastReceiver to handle it)

        with(NotificationManagerCompat.from(context)) {
            notify(NOTIFICATION_ID_CLIPBOARD, builder.build())
        }
    }
}
