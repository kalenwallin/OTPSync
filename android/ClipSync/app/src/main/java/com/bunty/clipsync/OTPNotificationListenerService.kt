package com.bunty.clipsync

import android.app.Notification
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class OTPNotificationListenerService : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d("OTPListener", "✅ NotificationListener CONNECTED")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        // Ignore our own notifications
        if (sbn.packageName == packageName) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString(" ") { it.toString() } ?: ""

        val fullMessage = listOf(title, text, bigText, lines)
            .joinToString(" ")
            .trim()

        if (fullMessage.isEmpty()) return

        Log.d(
            "OTPListener",
            "📩 From ${sbn.packageName}: $fullMessage"
        )

        // Let regex decide — no keyword gatekeeping
        val otp = HelperUtils.extractOTP(fullMessage)

        if (!otp.isNullOrBlank()) {
            Log.d("OTPListener", "🔐 OTP detected: $otp")
            copyToClipboard(otp)
        }
    }

    private fun copyToClipboard(otp: String) {
        // Use Ghost Activity to bypass background restrictions
        try {
            Log.d("OTPListener", "👻 Launching Ghost Activity to copy OTP...")
            ClipboardGhostActivity.copyToClipboard(this, otp)
        } catch (e: Exception) {
            Log.e("OTPListener", "❌ Failed to launch Ghost Activity", e)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w("OTPListener", "⚠️ NotificationListener DISCONNECTED")
    }
}