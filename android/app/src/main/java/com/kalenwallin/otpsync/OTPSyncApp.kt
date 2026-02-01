package com.kalenwallin.otpsync

import android.app.Application
import android.util.Log

class OTPSyncApp : Application() {
    override fun onCreate() {
        super.onCreate()

        // Initialize Convex Manager
        try {
            ConvexManager.initialize(this)
            Log.d("OTPSync", "Convex Manager Initialized")
        } catch (e: Exception) {
            Log.e("OTPSync", "Failed to initialize Convex: ${e.message}")
        }
        
        val deviceId = DeviceManager.getDeviceId(this)
        Log.d("OTPSync", "Device ID: $deviceId")
    }
}
