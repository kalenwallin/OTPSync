package com.bunty.clipsync

import android.content.Context
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * ConvexManager - Handles all Convex backend operations
 * Replaces FirestoreManager for Convex-based real-time sync
 */
object ConvexManager {
    private const val TAG = "ConvexManager"
    
    private val json = Json { 
        ignoreUnknownKeys = true 
        isLenient = true
    }
    
    // Initialize the manager (called from Application)
    fun initialize(context: Context) {
        // Pre-warm the deployment URL lookup
        val url = getDeploymentUrl(context)
        Log.d(TAG, "ConvexManager initialized with URL: $url")
    }

    // Get Convex deployment URL from resources
    private fun getDeploymentUrl(context: Context): String {
        return try {
            context.getString(R.string.convex_url)
        } catch (e: Exception) {
            Log.e(TAG, "convex_url not found in resources", e)
            "https://YOUR_DEPLOYMENT.convex.cloud"
        }
    }

    // Dynamic Secret Retrieval
    private fun getSharedSecret(context: Context): String {
        return DeviceManager.getEncryptionKey(context)
    }

    // --- QR Parsing Strategy ---
    // Supports:
    // 1. JSON (New V1 Format) - Contains {server, secret, macId}
    // 2. Legacy - Fallback for older versions
    fun parseQRData(qrData: String): Map<String, Any>? {
        try {
            if (qrData.trim().startsWith("{")) {
                val jsonObject = JSONObject(qrData)
                val macId = jsonObject.optString("macId")
                val deviceName = jsonObject.optString("deviceName").ifEmpty {
                    jsonObject.optString("macDeviceName", "Mac")
                }
                val secret = jsonObject.optString("secret")
                val convexUrl = jsonObject.optString("convexUrl").ifEmpty {
                    jsonObject.optString("server", "")
                }

                if (macId.isNotEmpty()) {
                    return mapOf(
                        "macDeviceId" to macId,
                        "macDeviceName" to deviceName,
                        "convexUrl" to convexUrl,
                        "secret" to secret
                    )
                }
            }
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse QR data", e)
            return null
        }
    }

    // --- Encryption Helpers (AES-GCM) ---
    
    fun decryptData(context: Context, encryptedBase64: String): String {
        try {
            val encryptedBytes = Base64.decode(encryptedBase64, Base64.NO_WRAP)
            if (encryptedBytes.size < 28) return ""

            val keyBytes = hexStringToByteArray(getSharedSecret(context))
            val keySpec = SecretKeySpec(keyBytes, "AES")

            val iv = encryptedBytes.copyOfRange(0, 12)
            val ciphertext = encryptedBytes.copyOfRange(12, encryptedBytes.size)

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val gcmSpec = GCMParameterSpec(128, iv)

            cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)
            val plaintextBytes = cipher.doFinal(ciphertext)

            return String(plaintextBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            Log.e(TAG, "Decryption failed", e)
            throw e
        }
    }

    fun encryptData(context: Context, plainText: String): String {
        try {
            val keyBytes = hexStringToByteArray(getSharedSecret(context))
            val keySpec = SecretKeySpec(keyBytes, "AES")

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = ByteArray(12)
            SecureRandom().nextBytes(iv)

            val gcmSpec = GCMParameterSpec(128, iv)
            cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)

            val ciphertext = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))

            val combined = ByteArray(iv.size + ciphertext.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)

            return Base64.encodeToString(combined, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "Encryption failed", e)
            return plainText
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

    // --- HTTP Helpers ---
    
    private suspend fun httpPost(context: Context, endpoint: String, body: JsonObject): JsonObject {
        return withContext(Dispatchers.IO) {
            val url = URL("${getDeploymentUrl(context)}/api/$endpoint")
            val connection = url.openConnection() as HttpURLConnection
            
            try {
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true
                connection.connectTimeout = 30000
                connection.readTimeout = 30000
                
                OutputStreamWriter(connection.outputStream).use { writer ->
                    writer.write(body.toString())
                    writer.flush()
                }
                
                val responseCode = connection.responseCode
                val responseStream = if (responseCode in 200..299) {
                    connection.inputStream
                } else {
                    connection.errorStream
                }
                
                val response = responseStream.bufferedReader().use { it.readText() }
                
                if (responseCode !in 200..299) {
                    throw ConvexException("HTTP $responseCode: $response")
                }
                
                json.parseToJsonElement(response).jsonObject
            } finally {
                connection.disconnect()
            }
        }
    }

    // --- Convex Query ---
    
    suspend fun <T> query(
        context: Context,
        functionName: String,
        args: Map<String, Any> = emptyMap(),
        deserializer: (JsonObject) -> T
    ): T? {
        val body = buildJsonObject {
            put("path", JsonPrimitive(functionName))
            put("args", buildJsonObject {
                args.forEach { (key, value) ->
                    when (value) {
                        is String -> put(key, JsonPrimitive(value))
                        is Number -> put(key, JsonPrimitive(value))
                        is Boolean -> put(key, JsonPrimitive(value))
                    }
                }
            })
            put("format", JsonPrimitive("json"))
        }
        
        val response = httpPost(context, "query", body)
        
        val status = response["status"]?.jsonPrimitive?.content
        if (status != "success") {
            val errorMessage = response["errorMessage"]?.jsonPrimitive?.content ?: "Unknown error"
            throw ConvexException(errorMessage)
        }
        
        val value = response["value"]
        if (value == null || value.toString() == "null") {
            return null
        }
        
        return deserializer(value.jsonObject)
    }
    
    // Simple query that returns a primitive
    suspend fun queryBoolean(
        context: Context,
        functionName: String,
        args: Map<String, Any> = emptyMap()
    ): Boolean {
        val body = buildJsonObject {
            put("path", JsonPrimitive(functionName))
            put("args", buildJsonObject {
                args.forEach { (key, value) ->
                    when (value) {
                        is String -> put(key, JsonPrimitive(value))
                        is Number -> put(key, JsonPrimitive(value))
                        is Boolean -> put(key, JsonPrimitive(value))
                    }
                }
            })
            put("format", JsonPrimitive("json"))
        }
        
        val response = httpPost(context, "query", body)
        
        val status = response["status"]?.jsonPrimitive?.content
        if (status != "success") {
            return false
        }
        
        return response["value"]?.jsonPrimitive?.content?.toBoolean() ?: false
    }

    // --- Convex Mutation ---
    
    suspend fun <T> mutation(
        context: Context,
        functionName: String,
        args: Map<String, Any> = emptyMap(),
        deserializer: (String) -> T
    ): T {
        val body = buildJsonObject {
            put("path", JsonPrimitive(functionName))
            put("args", buildJsonObject {
                args.forEach { (key, value) ->
                    when (value) {
                        is String -> put(key, JsonPrimitive(value))
                        is Number -> put(key, JsonPrimitive(value))
                        is Boolean -> put(key, JsonPrimitive(value))
                    }
                }
            })
            put("format", JsonPrimitive("json"))
        }
        
        val response = httpPost(context, "mutation", body)
        
        val status = response["status"]?.jsonPrimitive?.content
        if (status != "success") {
            val errorMessage = response["errorMessage"]?.jsonPrimitive?.content ?: "Unknown error"
            throw ConvexException(errorMessage)
        }
        
        val value = response["value"]?.jsonPrimitive?.content ?: ""
        return deserializer(value)
    }
    
    suspend fun mutationVoid(
        context: Context,
        functionName: String,
        args: Map<String, Any> = emptyMap()
    ) {
        val body = buildJsonObject {
            put("path", JsonPrimitive(functionName))
            put("args", buildJsonObject {
                args.forEach { (key, value) ->
                    when (value) {
                        is String -> put(key, JsonPrimitive(value))
                        is Number -> put(key, JsonPrimitive(value))
                        is Boolean -> put(key, JsonPrimitive(value))
                    }
                }
            })
            put("format", JsonPrimitive("json"))
        }
        
        val response = httpPost(context, "mutation", body)
        
        val status = response["status"]?.jsonPrimitive?.content
        if (status != "success") {
            val errorMessage = response["errorMessage"]?.jsonPrimitive?.content ?: "Unknown error"
            throw ConvexException(errorMessage)
        }
    }

    // --- Polling Subscription ---
    
    fun subscribeToClipboard(
        context: Context,
        pairingId: String,
        intervalMs: Long = 500
    ): Flow<ConvexClipboardItem?> = flow {
        var lastItemId: String? = null
        
        while (true) {
            try {
                val item = query(
                    context,
                    "clipboard:getLatest",
                    mapOf("pairingId" to pairingId)
                ) { jsonObj ->
                    ConvexClipboardItem(
                        id = jsonObj["_id"]?.jsonPrimitive?.content ?: "",
                        creationTime = jsonObj["_creationTime"]?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong() ?: 0L,
                        content = jsonObj["content"]?.jsonPrimitive?.content ?: "",
                        pairingId = jsonObj["pairingId"]?.jsonPrimitive?.content ?: "",
                        sourceDeviceId = jsonObj["sourceDeviceId"]?.jsonPrimitive?.content ?: "",
                        type = jsonObj["type"]?.jsonPrimitive?.content ?: "text"
                    )
                }
                
                // Only emit if item changed
                if (item != null && item.id != lastItemId) {
                    lastItemId = item.id
                    emit(item)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Clipboard subscription error", e)
            }
            
            delay(intervalMs)
        }
    }.flowOn(Dispatchers.IO)

    // --- Pairing Operations ---

    suspend fun createPairing(
        context: Context,
        qrData: Map<String, Any>,
        onSuccess: (String) -> Unit,
        onFailure: (Exception) -> Unit
    ) {
        val androidDeviceId = DeviceManager.getDeviceId(context)
        val androidDeviceName = DeviceManager.getAndroidDeviceName()
        val macDeviceId = qrData["macDeviceId"] as? String ?: ""
        val macDeviceName = qrData["macDeviceName"] as? String ?: "Mac"
        val secret = qrData["secret"] as? String
        val convexUrl = qrData["convexUrl"] as? String

        // Save encryption key
        if (!secret.isNullOrEmpty()) {
            DeviceManager.saveEncryptionKey(context, secret)
            Log.d(TAG, "Secure Key Swapped & Saved ✓")
        }
        
        // Save Convex URL if provided
        if (!convexUrl.isNullOrEmpty()) {
            // Store convex URL for this pairing
            context.getSharedPreferences("clipsync_prefs", Context.MODE_PRIVATE)
                .edit()
                .putString("convex_url", convexUrl)
                .apply()
        }

        try {
            val pairingId = mutation(
                context,
                "pairings:create",
                mapOf(
                    "androidDeviceId" to androidDeviceId,
                    "androidDeviceName" to androidDeviceName,
                    "macDeviceId" to macDeviceId,
                    "macDeviceName" to macDeviceName
                )
            ) { it }

            DeviceManager.savePairing(
                context = context,
                pairingId = pairingId,
                macDeviceId = macDeviceId,
                macDeviceName = macDeviceName
            )

            Log.d(TAG, "Pairing created: $pairingId")
            onSuccess(pairingId)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create pairing", e)
            onFailure(e)
        }
    }

    // --- Clipboard Operations ---

    fun listenToClipboard(
        context: Context,
        onClipboardUpdate: (String) -> Unit
    ): Flow<ConvexClipboardItem?> {
        val pairingId = DeviceManager.getPairingId(context) 
            ?: return flow { emit(null) }
        
        return subscribeToClipboard(context, pairingId)
    }

    suspend fun sendClipboard(
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
        val encryptedContent = encryptData(context, text)

        try {
            mutation(
                context,
                "clipboard:send",
                mapOf(
                    "pairingId" to pairingId,
                    "content" to encryptedContent,
                    "sourceDeviceId" to deviceId,
                    "type" to "text"
                )
            ) { it }
            
            Log.d(TAG, "Clipboard sent successfully (Encrypted)")
            onSuccess()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send clipboard", e)
            onFailure(e)
        }
    }

    suspend fun clearPairing(
        context: Context,
        onSuccess: () -> Unit = {},
        onFailure: (Exception) -> Unit = {}
    ) {
        val pairingId = DeviceManager.getPairingId(context) ?: return

        try {
            mutationVoid(
                context,
                "pairings:remove",
                mapOf("pairingId" to pairingId)
            )
            
            Log.d(TAG, "Pairing cleared from Convex")
            DeviceManager.clearPairing(context)
            onSuccess()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear pairing", e)
            onFailure(e)
        }
    }

    suspend fun clearClipboard(
        context: Context,
        onSuccess: () -> Unit = {},
        onFailure: (Exception) -> Unit = {}
    ) {
        val pairingId = DeviceManager.getPairingId(context)
        if (pairingId == null) {
            onFailure(Exception("No pairing ID found"))
            return
        }

        try {
            mutation(
                context,
                "clipboard:clear",
                mapOf("pairingId" to pairingId)
            ) { it.toIntOrNull() ?: 0 }
            
            Log.d(TAG, "Clipboard cleared successfully")
            onSuccess()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear clipboard", e)
            onFailure(e)
        }
    }
    
    // Check if pairing still exists
    suspend fun isPairingActive(context: Context, pairingId: String): Boolean {
        return try {
            queryBoolean(
                context,
                "pairings:exists",
                mapOf("pairingId" to pairingId)
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check pairing status", e)
            true // Assume active on error
        }
    }

    // Get latest clipboard item (used by accessibility service polling)
    suspend fun getLatestClipboard(context: Context): ConvexClipboardItem? {
        val pairingId = DeviceManager.getPairingId(context) ?: return null
        val deviceId = DeviceManager.getDeviceId(context)
        
        return try {
            query(
                context,
                "clipboard:getLatest",
                mapOf("pairingId" to pairingId)
            ) { jsonObj ->
                val rawContent = jsonObj["content"]?.jsonPrimitive?.content ?: ""
                val sourceDeviceId = jsonObj["sourceDeviceId"]?.jsonPrimitive?.content ?: ""
                
                // Skip items from this device
                if (sourceDeviceId == deviceId) {
                    return@query null
                }
                
                // Decrypt content
                val decryptedContent = try {
                    decryptData(context, rawContent)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to decrypt clipboard content", e)
                    rawContent
                }
                
                ConvexClipboardItem(
                    id = jsonObj["_id"]?.jsonPrimitive?.content ?: "",
                    creationTime = jsonObj["_creationTime"]?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong() ?: 0L,
                    content = decryptedContent,
                    pairingId = jsonObj["pairingId"]?.jsonPrimitive?.content ?: "",
                    sourceDeviceId = sourceDeviceId,
                    type = jsonObj["type"]?.jsonPrimitive?.content ?: "text"
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get latest clipboard", e)
            null
        }
    }
}

// Exception class
class ConvexException(message: String) : Exception(message)

// Data classes
@Serializable
data class ConvexClipboardItem(
    val id: String,
    val creationTime: Long,
    val content: String,
    val pairingId: String,
    val sourceDeviceId: String,
    val type: String
)

@Serializable
data class ConvexPairing(
    val id: String,
    val creationTime: Long,
    val androidDeviceId: String,
    val androidDeviceName: String,
    val macDeviceId: String,
    val macDeviceName: String,
    val status: String,
    val createdAt: Long
)
