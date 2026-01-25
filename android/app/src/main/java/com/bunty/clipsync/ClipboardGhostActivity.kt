package com.bunty.clipsync

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Toast

/**
 * --- Background Clipboard Hack ---
 * Android 10+ blocks background services from reading the clipboard.
 * This transparent Activity launches briefly to gain 'Foreground' status, 
 * reads/writes simple text, and then instantly closes.
 */
class ClipboardGhostActivity : Activity() {

    private var hasReadClipboard = false

    companion object {
        const val EXTRA_CLIP_TEXT = "extra_clip_text"
        
        // --- Intent Actions ---
        const val ACTION_READ = "action_read"
        const val ACTION_WRITE = "action_write"

        fun copyToClipboard(context: Context, text: String) {
            val intent = Intent(context, ClipboardGhostActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                action = ACTION_WRITE
                putExtra(EXTRA_CLIP_TEXT, text)
            }
            context.startActivity(intent)
        }

        fun readFromClipboard(context: Context) {
            val intent = Intent(context, ClipboardGhostActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                action = ACTION_READ
            }
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("ClipboardGhost", "onCreate: action=${intent.action}")

        // For WRITE mode, we can proceed immediately
        if (intent.action == ACTION_WRITE) {
            Log.d("ClipboardGhost", "onCreate: ACTION_WRITE")
            val text = intent.getStringExtra(EXTRA_CLIP_TEXT)
            if (!text.isNullOrEmpty()) {
                copyTextToClipboard(text)
            } else {
                Log.e("ClipboardGhost", "Write Action with empty text")
            }
            finish()
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
            } else {
                overridePendingTransition(0, 0)
            }
        } else {
            Log.d("ClipboardGhost", "onCreate: ACTION_READ - waiting for window focus")
        }
        // For READ mode, wait for onWindowFocusChanged
    }

    // --- Window Focus Logic (Read Mode) ---
    // We must wait for 'onWindowFocusChanged' to be true before Android allows clipboard read.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        
        // Only read when we have focus and it's a READ action
        if (hasFocus && intent.action == ACTION_READ && !hasReadClipboard) {
            hasReadClipboard = true
            // Post to ensure we're fully focused
            window.decorView.post {
                readClipboardAndFinish()
            }
        }
    }

    private fun readClipboardAndFinish() {
        try {
            Log.d("ClipboardGhost", "Accessing System Clipboard...")
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

            if (!clipboard.hasPrimaryClip()) {
                Log.d("ClipboardGhost", "Clipboard is empty (hasPrimaryClip=false)")
                return
            }

            val clipData = clipboard.primaryClip
            if (clipData == null || clipData.itemCount == 0) {
                Log.d("ClipboardGhost", "ClipData is null or empty")
                return
            }

            val item = clipData.getItemAt(0)
            val text = item.text?.toString() ?: ""
            Log.d("ClipboardGhost", "Ghost Read Success: '${text.take(20)}...'")

            if (text.isNotBlank()) {
                Log.d("ClipboardGhost", "Sending to Service callback...")
                ClipboardAccessibilityService.onClipboardRead(this, text)
            } else {
                Log.d("ClipboardGhost", "Read text is blank")
            }

        } catch (e: Exception) {
            Log.e("ClipboardGhost", "Critical: Failed to read clipboard in Ghost Activity", e)
        } finally {
            Log.d("ClipboardGhost", "Finishing Ghost Activity")
            finish()
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
            } else {
                overridePendingTransition(0, 0)
            }
        }
    }

    private fun copyTextToClipboard(text: String) {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("Copied Text", text)
            clipboard.setPrimaryClip(clip)
            Log.d("ClipboardGhost", "Successfully set clipboard via Ghost Activity")
            Toast.makeText(this, "Copied to clipboard", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Log.e("ClipboardGhost", "Failed to set clipboard", e)
        }
    }
}