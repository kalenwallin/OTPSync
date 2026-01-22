package com.bunty.clipsync

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        Log.d("FCM", "Refreshed token: $token")
        
        // If user is already paired, we might want to update the token in Firestore
        // For now, we just log it. The token retrieval is usually handled in UI or DeviceManager logic.
        val context = applicationContext
        if (DeviceManager.isPaired(context)) {
            // OPTIONAL: Update token in Firestore for this device
        }
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d("FCM", "From: ${remoteMessage.from}")

        // Check if message contains data payload.
        if (remoteMessage.data.isNotEmpty()) {
            Log.d("FCM", "Message data payload: ${remoteMessage.data}")
            
            // Handle clipboard data sync
            val clipboardContent = remoteMessage.data["content"]
            if (!clipboardContent.isNullOrEmpty()) {
                // Determine if it's an OTP
                val isOtp = HelperUtils.isOTP(clipboardContent) // Assuming HelperUtils exists or we implement logic here
                
                // Show Notification
                NotificationHelper(applicationContext).showClipboardNotification(clipboardContent, isOtp)
                
                // Also update local clipboard manager?
                // Note: updating clipboard from background is restricted in Android 10+.
                // The notification allows user to handle it manually.
            }
        }
    }
}
