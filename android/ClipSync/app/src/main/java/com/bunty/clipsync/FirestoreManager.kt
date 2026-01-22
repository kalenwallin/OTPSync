package com.bunty.clipsync

import android.content.Context
import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import org.json.JSONObject

object FirestoreManager {
    private val db = FirebaseFirestore.getInstance()

    // Hardcoded shared secret (Must match Mac side)
    private const val SHARED_SECRET_HEX = "5D41402ABC4B2A76B9719D911017C59228B4637452F80776313460C451152033"

    // Parse QR code data - Supports Encrypted and Legacy formats
    fun parseQRData(qrData: String): Map<String, Any>? {
        Log.d("FirestoreManager", "Parsing QR Data (Length: ${qrData.length})")

        var jsonDataString = qrData

        // 1. Try to Decrypt if it doesn't look like JSON/Legacy
        if (!qrData.trim().startsWith("{") && !qrData.contains("|")) {
            Log.d("FirestoreManager", "Data looks encrypted, attempting decryption...")
            try {
                val decrypted = decryptData(qrData)
                if (decrypted.isNotEmpty()) {
                    Log.d("FirestoreManager", "Decryption success! JSON: $decrypted")
                    jsonDataString = decrypted
                }
            } catch (e: Exception) {
                Log.e("FirestoreManager", "Decryption failed: ${e.message}")
                // Don't return null yet, maybe it's just a raw ID...
            }
        }

        return try {
            // Case 1: JSON Format (New Mac App)
            if (jsonDataString.trim().startsWith("{")) {
                val jsonObject = JSONObject(jsonDataString)
                val macId = jsonObject.optString("macId")
                // Check both "deviceName" and "macDeviceName" just in case
                val deviceName = jsonObject.optString("deviceName").ifEmpty {
                    jsonObject.optString("macDeviceName", "Mac")
                }

                if (macId.isNotEmpty()) {
                    return mapOf(
                        "macDeviceId" to macId,
                        "macDeviceName" to deviceName,
                        "serverRegion" to jsonObject.optString("server", "IN")
                    )
                }
            }

            // Case 2: Legacy Pipe Format "ID|Name" (Old version)
            val parts = jsonDataString.split("|")
            if (parts.size >= 2) {
                return mapOf(
                    "macDeviceId" to parts[0],
                    "macDeviceName" to (parts.getOrNull(1) ?: "Mac"),
                    "serverRegion" to "IN"
                )
            }

            // Case 3: Just ID (Raw or Failed Decryption Fallback)
            if (jsonDataString.isNotEmpty() && !jsonDataString.contains("|") && !jsonDataString.contains("{")) {
                return mapOf(
                    "macDeviceId" to jsonDataString,
                    "macDeviceName" to "Mac",
                    "serverRegion" to "IN"
                )
            }

            Log.e("FirestoreManager", "Invalid QR format")
            null
        } catch (e: Exception) {
            Log.e("FirestoreManager", "Failed to parse QR data", e)
            null
        }
    }

    // Decrypt AES-GCM Base64 String
    private fun decryptData(encryptedBase64: String): String {
        try {
            val encryptedBytes = android.util.Base64.decode(encryptedBase64, android.util.Base64.NO_WRAP)
            
            // Expected format: IV (12 bytes) + Ciphertext + Tag (16 bytes)
            if (encryptedBytes.size < 28) return ""

            val keyBytes = hexStringToByteArray(SHARED_SECRET_HEX)
            val keySpec = javax.crypto.spec.SecretKeySpec(keyBytes, "AES")

            // Extract IV
            val iv = encryptedBytes.copyOfRange(0, 12)
            val ciphertext = encryptedBytes.copyOfRange(12, encryptedBytes.size)

            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            val gcmSpec = javax.crypto.spec.GCMParameterSpec(128, iv)

            cipher.init(javax.crypto.Cipher.DECRYPT_MODE, keySpec, gcmSpec)
            val plaintextBytes = cipher.doFinal(ciphertext)

            return String(plaintextBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            // Log.e("FirestoreManager", "Decryption error", e) // Optional logging
            throw e
        }
    }

    // Encrypt AES-GCM -> Base64 String
    private fun encryptData(plainText: String): String {
        try {
            val keyBytes = hexStringToByteArray(SHARED_SECRET_HEX)
            val keySpec = javax.crypto.spec.SecretKeySpec(keyBytes, "AES")

            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            
            // Generate random IV
            val iv = ByteArray(12)
            java.security.SecureRandom().nextBytes(iv)
            
            val gcmSpec = javax.crypto.spec.GCMParameterSpec(128, iv)
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, keySpec, gcmSpec)

            val ciphertext = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))

            // Combine IV + Ciphertext
            val combined = ByteArray(iv.size + ciphertext.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)

            return android.util.Base64.encodeToString(combined, android.util.Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("FirestoreManager", "Encryption failed", e)
            return plainText // Fallback (should ideally handle error better)
        }
    }

    private fun hexStringToByteArray(s: String): ByteArray {
        val len = s.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(s[i], 16) shl 4) + Character.digit(s[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }

    // Create pairing in Firestore
    fun createPairing(
        context: Context,
        qrData: Map<String, Any>,
        onSuccess: (String) -> Unit,
        onFailure: (Exception) -> Unit
    ) {
        val androidDeviceId = DeviceManager.getDeviceId(context)
        val androidDeviceName = DeviceManager.getAndroidDeviceName()
        val macDeviceId = qrData["macDeviceId"] as? String ?: ""
        val macDeviceName = qrData["macDeviceName"] as? String ?: "Mac"

        val pairingData = hashMapOf<String, Any>(
            "androidDeviceId" to androidDeviceId,
            "androidDeviceName" to androidDeviceName,
            "macDeviceId" to macDeviceId,
            "macId" to macDeviceId,
            "macDeviceName" to macDeviceName,
            "createdAt" to System.currentTimeMillis(),
            "timestamp" to com.google.firebase.Timestamp.now(),
            "status" to "active"
        )

        // Helper to actually create the NEW pairing
        fun createNewPairing() {
            db.collection("pairings")
                .add(pairingData)
                .addOnSuccessListener { documentReference ->
                    val pairingId = documentReference.id
                    Log.d("FirestoreManager", "Pairing created: $pairingId")
                    documentReference.update("pairingId", pairingId)

                    DeviceManager.savePairing(
                        context = context,
                        pairingId = pairingId,
                        macDeviceId = macDeviceId,
                        macDeviceName = macDeviceName
                    )

                    onSuccess(pairingId)
                }
                .addOnFailureListener { exception ->
                    Log.e("FirestoreManager", "Failed to create pairing", exception)
                    onFailure(exception)
                }
        }

        // Check for existing PREVIOUS pairing and delete it first
        val oldPairingId = DeviceManager.getPairingId(context)
        if (oldPairingId != null) {
            Log.d("FirestoreManager", "Found existing pairing ($oldPairingId). Deleting first...")
            db.collection("pairings").document(oldPairingId).delete()
                .addOnSuccessListener {
                    Log.d("FirestoreManager", "Old pairing deleted. Creating new one...")
                    createNewPairing()
                }
                .addOnFailureListener { e ->
                    Log.w("FirestoreManager", "Failed to delete old pairing. Creating new one anyway...", e)
                    // Proceed even if delete fails (e.g. already deleted or permission issue)
                    createNewPairing()
                }
        } else {
            // No existing pairing, just create new one
            createNewPairing()
        }
    }

    // Listen to clipboard changes from Firestore (DECRYPTING)
    fun listenToClipboard(
        context: Context,
        onClipboardUpdate: (String) -> Unit
    ): ListenerRegistration? {
        val pairingId = DeviceManager.getPairingId(context) ?: return null
        val currentDeviceId = DeviceManager.getDeviceId(context)

        return db.collection("clipboardItems")
            .whereEqualTo("pairingId", pairingId)
            .orderBy("timestamp", com.google.firebase.firestore.Query.Direction.DESCENDING)
            .limit(1)
            .addSnapshotListener { snapshots, error ->
                if (error != null) {
                    Log.e("FirestoreManager", "Listen failed", error)
                    return@addSnapshotListener
                }

                snapshots?.documents?.firstOrNull()?.let { document ->
                    val encryptedContent = document.getString("content")
                    val sourceDeviceId = document.getString("sourceDeviceId")

                    // Only update if it came from a different device (Mac)
                    if (encryptedContent != null && sourceDeviceId != currentDeviceId) {
                         // DECRYPT HERE
                         try {
                             val decryptedContent = decryptData(encryptedContent)
                             if (decryptedContent.isNotEmpty()) {
                                 onClipboardUpdate(decryptedContent)
                             }
                         } catch (e: Exception) {
                             Log.e("FirestoreManager", "Failed to decrypt incoming clipboard", e)
                         }
                    }
                }
            }
    }

    // Send clipboard to Firestore (ENCRYPTING)
    fun sendClipboard(
        context: Context,
        text: String,
        onSuccess: () -> Unit = {},
        onFailure: (Exception) -> Unit = {}
    ) {
        val pairingId = DeviceManager.getPairingId(context)
        if (pairingId == null) {
            onFailure(Exception("No pairing ID found"))
            return
        }
        
        val deviceId = DeviceManager.getDeviceId(context)

        // ENCRYPT HERE
        val encryptedContent = encryptData(text)

        val clipboardData = hashMapOf<String, Any>(
            "content" to encryptedContent,
            "pairingId" to pairingId,
            "sourceDeviceId" to deviceId,
            "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
            "type" to "text"
        )

        db.collection("clipboardItems")
            .add(clipboardData)
            .addOnSuccessListener {
                Log.d("FirestoreManager", "Clipboard sent successfully (Encrypted)")
                onSuccess()
            }
            .addOnFailureListener { exception ->
                Log.e("FirestoreManager", "Failed to send clipboard", exception)
                onFailure(exception)
            }
    }

    // Clear pairing from Firestore
    fun clearPairing(
        context: Context,
        onSuccess: () -> Unit = {},
        onFailure: (Exception) -> Unit = {}
    ) {
        val pairingId = DeviceManager.getPairingId(context) ?: return

        db.collection("pairings")
            .document(pairingId)
            .delete()
            .addOnSuccessListener {
                Log.d("FirestoreManager", "Pairing cleared from Firestore")
                DeviceManager.clearPairing(context)
                onSuccess()
            }
            .addOnFailureListener { exception ->
                Log.e("FirestoreManager", "Failed to clear pairing", exception)
                onFailure(exception)
            }
    }

    // Clear CLIPBOARD history for this pairing
    fun clearClipboard(
        context: Context,
        onSuccess: () -> Unit = {},
        onFailure: (Exception) -> Unit = {}
    ) {
        val pairingId = DeviceManager.getPairingId(context)
        if (pairingId == null) {
            onFailure(Exception("No pairing ID found"))
            return
        }

        db.collection("clipboardItems")
            .whereEqualTo("pairingId", pairingId)
            .get()
            .addOnSuccessListener { snapshot ->
                val batch = db.batch()
                for (doc in snapshot.documents) {
                    batch.delete(doc.reference)
                }
                batch.commit()
                    .addOnSuccessListener {
                        Log.d("FirestoreManager", "Clipboard cleared successfully")
                        onSuccess()
                    }
                    .addOnFailureListener { e ->
                        Log.e("FirestoreManager", "Failed to commit batch delete", e)
                        onFailure(e)
                    }
            }
            .addOnFailureListener { e ->
                Log.e("FirestoreManager", "Failed to fetch clipboard items for deletion", e)
                onFailure(e)
            }
    }
}
