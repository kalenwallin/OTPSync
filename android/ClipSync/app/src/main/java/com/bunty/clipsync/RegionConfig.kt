package com.bunty.clipsync

import android.content.Context
import com.google.firebase.FirebaseOptions

object RegionConfig {

    const val REGION_INDIA = "IN"
    const val REGION_US = "US"

    // US Project Credentials (clipsync1-c3c3c)
    private const val US_PROJECT_ID = "clipsync1-c3c3c" 
    private const val US_APPLICATION_ID = "1:421995011629:android:1895288aa3d34ca18a22a4"
    private const val US_API_KEY = "AIzaSyBVstWdjwanCsNXHBjn0oaHC160PDL4iQ"

    fun getOptionsForRegion(context: Context, region: String): FirebaseOptions? {
        return when (region) {
            REGION_US -> {
                FirebaseOptions.Builder()
                    .setProjectId(US_PROJECT_ID)
                    .setApplicationId(US_APPLICATION_ID)
                    .setApiKey(US_API_KEY)
                    .setStorageBucket("clipsync1-c3c3c.firebasestorage.app")
                    .build()
            }
            REGION_INDIA -> {
                // Return null to indicate "Use Default from google-services.json"
                null
            }
            else -> null // Default
        }
    }
}
