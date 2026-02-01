package com.kalenwallin.otpsync

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import java.util.UUID

object DeviceManager {
    private const val PREFS_NAME = "clipsync_prefs"
    
    // --- Preference Keys ---
    private const val KEY_PAIRED = "is_paired"
    private const val KEY_PAIRED_DEVICE_ID = "paired_device_id"
    private const val KEY_PAIRED_DEVICE_NAME = "paired_device_name"
    private const val KEY_PAIRING_ID = "pairing_id"
    private const val KEY_ENCRYPTION_KEY = "encryption_key" 
    private const val KEY_ANDROID_DEVICE_ID = "android_device_id"
    private const val KEY_ANDROID_DEVICE_NAME = "android_device_name"
    private const val KEY_SYNC_TO_MAC = "sync_to_mac"
    private const val KEY_SYNC_FROM_MAC = "sync_from_mac"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun getDeviceId(context: Context): String {
        var deviceId = getPrefs(context).getString(KEY_ANDROID_DEVICE_ID, null)
        if (deviceId == null) {
            deviceId = "${Build.MODEL}_${UUID.randomUUID()}"
            getPrefs(context).edit().putString(KEY_ANDROID_DEVICE_ID, deviceId).apply()
            println(" Generated new Device ID: $deviceId")
        } else {
            println(" Using existing Device ID: $deviceId")
        }
        return deviceId
    }

    fun isPaired(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_PAIRED, false)
    }

    fun savePairing(
        context: Context,
        pairingId: String,
        macDeviceId: String,
        macDeviceName: String
    ) {
        val androidDeviceName = getAndroidDeviceName()

        getPrefs(context).edit().apply {
            putBoolean(KEY_PAIRED, true)
            putString(KEY_PAIRING_ID, pairingId)
            putString(KEY_PAIRED_DEVICE_ID, macDeviceId)
            putString(KEY_PAIRED_DEVICE_NAME, macDeviceName)
            putString(KEY_ANDROID_DEVICE_NAME, androidDeviceName)
            apply()
        }
    }

    fun getPairedMacDeviceName(context: Context): String {
        return getPrefs(context).getString(KEY_PAIRED_DEVICE_NAME, "Unknown Device") ?: "Unknown Device"
    }

    fun getAndroidDeviceName(): String {
        val manufacturer = Build.MANUFACTURER ?: ""
        val model = Build.MODEL ?: "Android"

        return when {
            model.contains("sdk", ignoreCase = true) -> "Android Emulator"
            manufacturer.isNotEmpty() -> {
                val capitalizedManufacturer = manufacturer.replaceFirstChar {
                    if (it.isLowerCase()) it.titlecase() else it.toString()
                }
                "$capitalizedManufacturer $model"
            }
            else -> model
        }.take(20)
    }

    fun getPairingId(context: Context): String? {
        return getPrefs(context).getString(KEY_PAIRING_ID, null)
    }

    fun clearPairing(context: Context) {
        getPrefs(context).edit().apply {
            putBoolean(KEY_PAIRED, false)
            remove(KEY_PAIRING_ID)
            remove(KEY_PAIRED_DEVICE_ID)
            remove(KEY_PAIRED_DEVICE_NAME)
            remove(KEY_PAIRED_DEVICE_NAME)
            remove(KEY_ENCRYPTION_KEY) // Clear key on unpair
            // Keep sync preferences or reset? Let's keep them for convenience.
            apply()
        }
    }

    // Dynamic Encryption Key
    fun getEncryptionKey(context: Context): String {
        // Key is set during QR pairing - no fallback needed
        return getPrefs(context).getString(KEY_ENCRYPTION_KEY, null) 
            ?: "" // Empty means not paired yet
    }

    fun saveEncryptionKey(context: Context, key: String) {
        getPrefs(context).edit().putString(KEY_ENCRYPTION_KEY, key).apply()
    }

    fun isSyncToMacEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_SYNC_TO_MAC, true) // Default true
    }

    fun setSyncToMacEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_SYNC_TO_MAC, enabled).apply()
    }

    fun isSyncFromMacEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_SYNC_FROM_MAC, true) // Default true
    }

    fun setSyncFromMacEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_SYNC_FROM_MAC, enabled).apply()
    }
}
