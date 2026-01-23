package com.bunty.clipsync

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.WindowManager
import android.view.Gravity
import android.graphics.PixelFormat
import android.view.View
import android.provider.Settings

class ClipboardAccessibilityService : AccessibilityService() {

    private var ignoreNextChange = false
    private lateinit var clipboardManager: ClipboardManager
    private val handler = Handler(Looper.getMainLooper())
    private var lastUploadedContent: String = ""
    private var lastClipboardContent: String = ""
    private var lastEventTime = 0L

    private var lastRootScanTime = 0L
    private var firestoreListener: com.google.firebase.firestore.ListenerRegistration? = null

    // Direct clipboard listener commented out in favor of accessibility events
    // for broader compatibility on Android 10+

    companion object {
        private const val TAG = "ClipSync_Service"
        var isRunning = false

        @Volatile
        var lastSyncedContent: String = ""

        fun onClipboardRead(context: Context, text: String) {
            if (text.isBlank()) {
                Log.d(TAG, "Ignoring blank clipboard")
                return
            }

            if (text == lastSyncedContent) {
                return
            }

            lastSyncedContent = text
            uploadToFirestoreStatic(context.applicationContext, text)
        }

        private fun uploadToFirestoreStatic(context: Context, text: String) {
            try {
                FirestoreManager.sendClipboard(
                    context = context,
                    text = text,
                    onSuccess = {
                        // Upload successful
                    },
                    onFailure = { e: Exception ->
                        Log.e(TAG, "Upload Failed", e)
                        if (lastSyncedContent == text) {
                            lastSyncedContent = ""
                        }
                    }
                )
            } catch (e: Exception) {
                Log.e(TAG, "Exception in uploadToFirestoreStatic", e)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        Log.d(TAG, "Service Connected")

        try {
            // Configuration is handled via accessibility_service_config.xml
            // We do NOT override it here to avoid permission conflicts.

            Log.d(TAG, "Accessibility configured")
            clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            Log.d(TAG, "Clipboard manager obtained")

            // Register direct clipboard listener
            // clipboardManager.addPrimaryClipChangedListener(clipListener)
            // Log.d(TAG, "Direct clipboard listener registered")

            Log.d(TAG, "Service initialized")
            startFirestoreListener()

        } catch (e: Exception) {
            Log.e(TAG, "Crash in onServiceConnected", e)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            val eventTime = event.eventTime
            // Debounce: Ignore events if they happen too close to the last one (1 second)
            // This prevents double-triggering if an app shows a Toast AND a Snackbar.
            if (eventTime - lastEventTime < 1000) {
                return
            }

            // Ignore events from our own app to prevent loops (e.g. reading our own "Copied" toast)
            if (event.packageName == packageName) {
                return
            }

            when (event.eventType) {
                // Detect "Copied" Toast messages
                AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> {
                    if (event.className == "android.widget.Toast") {
                        val text = event.text.toString()
                        if (text.contains("copied", ignoreCase = true)) {
                            lastEventTime = eventTime
                            handler.postDelayed({
                                handleClipboardChange("Toast Notification")
                            }, 50)
                        }
                    }
                }

                // Detect "Copy" interaction
                AccessibilityEvent.TYPE_VIEW_CLICKED,
                AccessibilityEvent.TYPE_VIEW_FOCUSED,
                AccessibilityEvent.TYPE_VIEW_SELECTED,
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                    val contentDesc = event.contentDescription?.toString() ?: ""
                    val eventText = event.text.joinToString(" ")
                    val isClick = (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED)

                    var triggerType: String? = null

                    // Logic:
                    // 1. If it's a CLICK, we accept "Copy" or "Copied".
                    // 2. If it's PASSIVE (Content Changed, etc.), we REJECT "Copy" (present tense) 
                    //    to avoid triggering when a menu opens. We only accept "Copied" (past) or ID match.

                    val hasCopy = (contentDesc.contains(
                        "copy",
                        ignoreCase = true
                    ) || eventText.contains("copy", ignoreCase = true))
                    val hasCopied = (contentDesc.contains(
                        "copied",
                        ignoreCase = true
                    ) || eventText.contains("copied", ignoreCase = true))
                    val isCopyright =
                        (contentDesc.contains("copyright", ignoreCase = true) || eventText.contains(
                            "copyright",
                            ignoreCase = true
                        ))

                    if (!isCopyright) {
                        if (isClick && hasCopy) {
                            triggerType = "Click (Copy Button)"
                        } else if (hasCopied) {
                            triggerType = "Passive (Content Copied)"
                        } else if (hasCopy && !isClick) {
                            // It has "Copy" but it wasn't a click. It's likely a menu opening.
                            // We IGNORE this specific text match.
                        }
                    }

                    // 2. Event Source Deep Search
                    // Only try if simple match failed. 
                    // IMPORTANT: We pass 'isClick' to dfsFindCopy to apply the same strict rules depths-wise.
                    var source = event.source
                    if (triggerType == null && source != null) {
                        try {
                            if (dfsFindCopy(source, isClick = isClick)) {
                                triggerType = "Deep Search (Source)"
                            }
                        } finally {
                            source.recycle()
                        }
                    }

                    // 3. Fallback: Check the ENTIRE screen (Root Window)
                    // Optimization: Root scan is expensive.
                    // - If WINDOW_STATE_CHANGED (New screen/popup): Scan immediately.
                    // - Otherwise (Content change/Scroll): Throttle it to once every 2 seconds.
                    
                    val now = System.currentTimeMillis()
                    val isWindowStateChange = (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED)
                    val timeSinceLastRootScan = now - lastRootScanTime
                    
                    if (triggerType == null) {
                         // Only scan if it's a new window OR we haven't scanned in a while
                         if (isWindowStateChange || timeSinceLastRootScan > 2000) {
                            val rootNode = rootInActiveWindow
                            if (rootNode != null) {
                                try {
                                    lastRootScanTime = now
                                    // For root scan (always passive), we treat isClick = false
                                    if (dfsFindCopy(rootNode, isClick = false)) {
                                        triggerType = "Root Window Scan"
                                    }
                                } finally {
                                    rootNode.recycle()
                                }
                            }
                         }
                    }

                    if (triggerType != null) {
                        Log.d(TAG, "Clipboard change detected")
                        lastEventTime = eventTime
                        handler.postDelayed({
                            handleClipboardChange(triggerType)
                        }, 50)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onAccessibilityEvent", e)
        }
    }

    private fun dfsFindCopy(
        node: android.view.accessibility.AccessibilityNodeInfo?,
        depth: Int = 0,
        isClick: Boolean = false
    ): Boolean {
        if (node == null) return false
        if (depth > 5) return false
        if (!node.isVisibleToUser) return false // Optimization: Skip invisible nodes

        val text = node.text?.toString() ?: ""
        val contentDesc = node.contentDescription?.toString() ?: ""
        val viewId = node.viewIdResourceName ?: ""
        
        // Optimisation: A "Copy" button or "Copied" toast is rarely a paragraph of text.
        // If the text is huge, it's likely content, not a control. 
        // We skip string matching on huge text to save CPU, unless it's an ID match we are looking for.
        // "Copy to clipboard" is 17 chars. 30 is a safe upper limit.
        if ((text.length > 30 || contentDesc.length > 30) && viewId.isEmpty()) {
             // If ID is present, we still check it (e.g. smart_reply_action might have no text but a valid ID)
             // But if just text, skip.
             // Continuing directly to children might be safer than returning false?
             // Actually, if the container has long text but children are buttons, we MUST recurse.
             // So we just skip the *local* string check, but continue to loop children.
        } else {
            val combined = "$text $contentDesc $viewId".trim()
            if (combined.isNotEmpty()) {
                 // Log.d(TAG, "Inspecting[D$depth]: '$combined'") // Removed verbose logging
            }
            
            if (combined.contains("copyright", ignoreCase = true)) return false

            val hasCopy = combined.contains("copy", ignoreCase = true)
            val hasCopied = combined.contains("copied", ignoreCase = true)
            val hasIdMatch = viewId.contains("copy", ignoreCase = true)

            // Strict Logic for Deep Search:
            if (isClick && hasCopy) {
                Log.d(TAG, "Deep search found Clickable Copy: '$combined'")
                return true
            }

            // Passive Mode (Content Changed):
            if (!isClick) {
                if (hasCopied) {
                    return true
                }
                if (hasIdMatch) {
                    return true
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                try {
                    if (dfsFindCopy(child, depth + 1, isClick)) {
                        return true
                    }
                } finally {
                    child.recycle()
                }
            }
        }
        return false
    }

    private fun getEventTypeName(eventType: Int): String {
        return when (eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED -> "VIEW_CLICKED"
            AccessibilityEvent.TYPE_VIEW_FOCUSED -> "VIEW_FOCUSED"
            AccessibilityEvent.TYPE_VIEW_SELECTED -> "VIEW_SELECTED"
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> "VIEW_TEXT_CHANGED"
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> "WINDOW_STATE_CHANGED"
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> "WINDOW_CONTENT_CHANGED"
            AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> "NOTIFICATION_STATE_CHANGED"
            else -> "UNKNOWN($eventType)"
        }
    }

    private fun handleClipboardChange(trigger: String = "Unknown") {
        if (!Settings.canDrawOverlays(this)) {
            Log.e(TAG, "Overlay Permission Missing! Cannot launch Ghost Activity.")
            return
        }

        Log.d(TAG, "Launching Ghost Activity [Trigger: $trigger]")
        try {
            ClipboardGhostActivity.readFromClipboard(this)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch Ghost Activity", e)
        }
    }



    private fun startFirestoreListener() {
        try {
            // Remove existing listener to prevent duplicates
            firestoreListener?.remove()
            
            firestoreListener = FirestoreManager.listenToClipboard(this) { content: String ->
                try {
                    if (content == lastSyncedContent || content == lastClipboardContent) {
                        return@listenToClipboard
                    }

                    ignoreNextChange = true
                    lastSyncedContent = content
                    lastClipboardContent = content

                    ClipboardGhostActivity.copyToClipboard(
                        this@ClipboardAccessibilityService,
                        content
                    )

                    handler.postDelayed({
                        ignoreNextChange = false
                    }, 2000)

                } catch (e: Exception) {
                    Log.e(TAG, "Error in Firestore listener", e)
                    ignoreNextChange = false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting Firestore listener", e)
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()

        try {
            if (::clipboardManager.isInitialized) {
                // clipboardManager.removePrimaryClipChangedListener(clipListener)
                Log.d(TAG, "Clipboard listener unregistered")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing clipboard listener", e)
        }

        // Stop Firestore listener
        firestoreListener?.remove()
        firestoreListener = null
        
        // Remove pending handler callbacks to prevent leaks
        handler.removeCallbacksAndMessages(null)
        
        isRunning = false
        Log.d(TAG, "Service destroyed")
    }
}




