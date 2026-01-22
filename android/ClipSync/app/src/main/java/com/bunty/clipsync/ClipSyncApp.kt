package com.bunty.clipsync

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth

class ClipSyncApp : Application() {
    override fun onCreate() {
        super.onCreate()

        // Initialize Firebase based on Region
        val region = DeviceManager.getTargetRegion(this)
        DeviceManager.initializedRegion = region // Record what we acted on
        val options = RegionConfig.getOptionsForRegion(this, region)

        try {
            if (options != null) {
                // Initialize with custom options (US presence)
                FirebaseApp.initializeApp(this, options)
                Log.d("ClipSync", "Initialized with Region: $region")
            } else {
                // Default (India) - uses google-services.json
                FirebaseApp.initializeApp(this)
                Log.d("ClipSync", "Initialized with Default Region (IN)")
            }
            
            // Fix: Sign in anonymously to satisfy Firestore Security Rules
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
