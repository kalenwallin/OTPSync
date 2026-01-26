package com.bunty.clipsync

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth

class ClipSyncApp : Application() {
    override fun onCreate() {
        super.onCreate()

        // --- Multi-Region Initialization ---
        // 1. Default App (India): Initialized automatically by google-services.json
        // 2. US App (Named): Initialized manually here
        
        try {
            // Default (India)
            Log.d("ClipSync", "Default App (IN) Initialized. Project ID: ${FirebaseApp.getInstance().options.projectId}")

            // Initialize named US App
            val usOptions = RegionConfig.getOptionsForRegion(this, RegionConfig.REGION_US)
            if (usOptions != null) {
                FirebaseApp.initializeApp(this, usOptions, "ClipSyncUS")
                Log.d("ClipSync", "Secondary App (US) Initialized. Project ID: ${FirebaseApp.getInstance("ClipSyncUS").options.projectId}")
            }
            
            // --- Anonymous Authentication (Required for Firestore Rules) ---
            // Note: We might need to auth on BOTH apps if rules require it. 
            // For now, auth on default.
            signInAnonymously()
            
        } catch (e: Exception) {
             Log.e("ClipSync", "Failed to initialize Firebase: ${e.message}")
        }
        val deviceId = DeviceManager.getDeviceId(this)
        Log.d("ClipSync", "Device ID: $deviceId")
    }

    private fun signInAnonymously() {
        val auth = FirebaseAuth.getInstance()
        if (auth.currentUser == null) {
            auth.signInAnonymously()
                .addOnSuccessListener {
                    Log.d("ClipSync", "Anonymous Auth Success: ${it.user?.uid}")
                }
                .addOnFailureListener {
                    Log.e("ClipSync", "Anonymous Auth Failed", it)
                }
        } else {
            Log.d("ClipSync", "Already authenticated: ${auth.currentUser?.uid}")
        }
    }
}
