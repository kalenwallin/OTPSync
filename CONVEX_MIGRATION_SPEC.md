# OTPSync: Firebase to Convex Migration Specification

**Version:** 1.0  
**Date:** January 31, 2026  
**Status:** Draft  

---

## Executive Summary

This document specifies the complete migration of OTPSync from Firebase (Firestore) to Convex as the backend-as-a-service platform. OTPSync is a cross-platform clipboard synchronization app between macOS and Android devices, featuring end-to-end AES-256-GCM encryption.

---

## Table of Contents

1. [Current Architecture](#1-current-architecture)
2. [Target Architecture](#2-target-architecture)
3. [Data Model Migration](#3-data-model-migration)
4. [Backend Implementation (Convex)](#4-backend-implementation-convex)
5. [macOS Client Migration](#5-macos-client-migration)
6. [Android Client Migration](#6-android-client-migration)
7. [Security Considerations](#7-security-considerations)
8. [Migration Strategy](#8-migration-strategy)
9. [Testing Plan](#9-testing-plan)
10. [Manual Testing Instructions](#10-manual-testing-instructions)

---

## 1. Current Architecture

### 1.1 Firebase Services in Use

| Service | Usage |
|---------|-------|
| **Firestore** | Real-time database for pairings and clipboard items |
| **Firebase Messaging** | Push notifications (Android) |

### 1.2 Current Collections

#### `pairings` Collection
```javascript
{
  pairingId: string,           // Document ID (auto-generated)
  androidDeviceId: string,     // Unique Android device identifier
  androidDeviceName: string,   // "Samsung Galaxy S24"
  macId: string,               // Unique Mac device identifier
  macDeviceId: string,         // Same as macId
  macDeviceName: string,       // "Bhanu's Mac"
  createdAt: number,           // Unix timestamp (ms)
  timestamp: Timestamp,        // Firestore server timestamp
  status: string               // "active"
}
```

#### `clipboardItems` Collection
```javascript
{
  content: string,             // AES-256-GCM encrypted (Base64)
  pairingId: string,           // Reference to pairing document
  sourceDeviceId: string,      // Device that sent the clipboard
  timestamp: Timestamp,        // Firestore server timestamp
  type: string                 // "text"
}
```

### 1.3 Current Data Flow

```
┌─────────────┐    QR Code     ┌─────────────┐
│   macOS     │◄──────────────►│   Android   │
│   Client    │                │   Client    │
└─────┬───────┘                └──────┬──────┘
      │                               │
      │  Firestore Listeners          │
      │  (Real-time Sync)             │
      ▼                               ▼
┌─────────────────────────────────────────────┐
│              Firebase Firestore             │
│  ┌─────────────┐    ┌───────────────────┐  │
│  │  pairings   │    │  clipboardItems   │  │
│  └─────────────┘    └───────────────────┘  │
└─────────────────────────────────────────────┘
```

### 1.4 Current Encryption Model

- **Algorithm:** AES-256-GCM
- **Key:** 256-bit hex string (64 characters)
- **IV:** 12 bytes (randomly generated per encryption)
- **Format:** `Base64(IV || Ciphertext || AuthTag)`
- **Key Exchange:** Via QR code (JSON with `secret` field)

---

## 2. Target Architecture

### 2.1 Convex Services

| Service | Usage |
|---------|-------|
| **Convex Database** | Real-time reactive database |
| **Convex Functions** | Queries, Mutations, Actions |
| **Convex Subscriptions** | Real-time listeners |

### 2.2 Architecture Diagram

```
┌─────────────┐    QR Code     ┌─────────────┐
│   macOS     │◄──────────────►│   Android   │
│   (Swift)   │                │  (Kotlin)   │
└─────┬───────┘                └──────┬──────┘
      │                               │
      │  ConvexClient.subscribe()     │
      │  ConvexClient.mutation()      │
      ▼                               ▼
┌─────────────────────────────────────────────┐
│               Convex Backend                │
│  ┌─────────────────────────────────────┐   │
│  │           convex/                    │   │
│  │  ├── schema.ts                       │   │
│  │  ├── pairings.ts (queries/mutations)│   │
│  │  └── clipboard.ts (queries/mutations)│  │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────┐    ┌───────────────────┐  │
│  │  pairings   │    │  clipboardItems   │  │
│  │   (table)   │    │     (table)       │  │
│  └─────────────┘    └───────────────────┘  │
└─────────────────────────────────────────────┘
```

### 2.3 Key Benefits of Convex

1. **Native Swift SDK** - First-class Swift support with Combine/async-await
2. **Native Kotlin SDK** - First-class Android support with Coroutines/Flow
3. **Real-time by Default** - All queries are reactive subscriptions
4. **TypeScript Backend** - Type-safe schema and functions
5. **Automatic Scaling** - No infrastructure management
6. **Simpler Pricing** - Generous free tier

---

## 3. Data Model Migration

### 3.1 Convex Schema Definition

Create `convex/schema.ts`:

```typescript
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  pairings: defineTable({
    // Device identifiers
    androidDeviceId: v.string(),
    androidDeviceName: v.string(),
    macDeviceId: v.string(),
    macDeviceName: v.string(),
    
    // Metadata
    status: v.string(),  // "active" | "inactive"
    createdAt: v.number(), // Unix timestamp (ms)
  })
    .index("by_macId", ["macDeviceId"])
    .index("by_androidId", ["androidDeviceId"])
    .index("by_status", ["status"]),

  clipboardItems: defineTable({
    // Content (encrypted)
    content: v.string(),  // AES-256-GCM encrypted, Base64 encoded
    
    // References
    pairingId: v.id("pairings"),
    sourceDeviceId: v.string(),
    
    // Metadata
    type: v.string(),  // "text" | "image" (future)
  })
    .index("by_pairing", ["pairingId"])
    .index("by_pairing_time", ["pairingId"]),
});
```

### 3.2 Data Mapping

| Firebase Field | Convex Field | Notes |
|----------------|--------------|-------|
| `document.id` | `_id` | Auto-generated Convex ID |
| `timestamp` (server) | `_creationTime` | Auto-generated by Convex |
| `createdAt` (ms) | `createdAt` | Keep for backward compat |
| All other fields | Same names | Direct mapping |

---

## 4. Backend Implementation (Convex)

### 4.1 Project Structure

```
convex/
├── _generated/          # Auto-generated (do not edit)
├── schema.ts            # Database schema
├── pairings.ts          # Pairing functions
├── clipboard.ts         # Clipboard functions
└── tsconfig.json        # TypeScript config
```

### 4.2 Pairing Functions

Create `convex/pairings.ts`:

```typescript
import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

// Query: Get pairing by Mac device ID
export const getByMacId = query({
  args: { macDeviceId: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("pairings")
      .withIndex("by_macId", (q) => q.eq("macDeviceId", args.macDeviceId))
      .filter((q) => q.eq(q.field("status"), "active"))
      .first();
  },
});

// Query: Get pairing by ID
export const get = query({
  args: { pairingId: v.id("pairings") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.pairingId);
  },
});

// Query: Watch for new pairings (for Mac listening)
export const watchForPairing = query({
  args: { 
    macDeviceId: v.string(),
    sinceTimestamp: v.number() 
  },
  handler: async (ctx, args) => {
    const pairings = await ctx.db
      .query("pairings")
      .withIndex("by_macId", (q) => q.eq("macDeviceId", args.macDeviceId))
      .filter((q) => 
        q.and(
          q.eq(q.field("status"), "active"),
          q.gte(q.field("createdAt"), args.sinceTimestamp)
        )
      )
      .order("desc")
      .first();
    
    return pairings;
  },
});

// Mutation: Create new pairing (called by Android after QR scan)
export const create = mutation({
  args: {
    androidDeviceId: v.string(),
    androidDeviceName: v.string(),
    macDeviceId: v.string(),
    macDeviceName: v.string(),
  },
  handler: async (ctx, args) => {
    // Delete any existing pairing for this Android device
    const existingPairing = await ctx.db
      .query("pairings")
      .withIndex("by_androidId", (q) => q.eq("androidDeviceId", args.androidDeviceId))
      .first();
    
    if (existingPairing) {
      await ctx.db.delete(existingPairing._id);
    }

    // Create new pairing
    const pairingId = await ctx.db.insert("pairings", {
      androidDeviceId: args.androidDeviceId,
      androidDeviceName: args.androidDeviceName,
      macDeviceId: args.macDeviceId,
      macDeviceName: args.macDeviceName,
      status: "active",
      createdAt: Date.now(),
    });

    return pairingId;
  },
});

// Mutation: Delete pairing (unpair)
export const remove = mutation({
  args: { pairingId: v.id("pairings") },
  handler: async (ctx, args) => {
    // Delete all clipboard items for this pairing
    const clipboardItems = await ctx.db
      .query("clipboardItems")
      .withIndex("by_pairing", (q) => q.eq("pairingId", args.pairingId))
      .collect();
    
    for (const item of clipboardItems) {
      await ctx.db.delete(item._id);
    }

    // Delete the pairing
    await ctx.db.delete(args.pairingId);
  },
});
```

### 4.3 Clipboard Functions

Create `convex/clipboard.ts`:

```typescript
import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

// Query: Get latest clipboard item for a pairing
export const getLatest = query({
  args: { pairingId: v.id("pairings") },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("clipboardItems")
      .withIndex("by_pairing", (q) => q.eq("pairingId", args.pairingId))
      .order("desc")
      .first();
  },
});

// Query: Get clipboard history for a pairing
export const getHistory = query({
  args: { 
    pairingId: v.id("pairings"),
    limit: v.optional(v.number()) 
  },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("clipboardItems")
      .withIndex("by_pairing", (q) => q.eq("pairingId", args.pairingId))
      .order("desc")
      .take(args.limit ?? 50);
  },
});

// Mutation: Send clipboard item
export const send = mutation({
  args: {
    pairingId: v.id("pairings"),
    content: v.string(),       // Already encrypted by client
    sourceDeviceId: v.string(),
    type: v.string(),
  },
  handler: async (ctx, args) => {
    // Verify pairing exists
    const pairing = await ctx.db.get(args.pairingId);
    if (!pairing) {
      throw new Error("Pairing not found");
    }

    // Insert clipboard item
    const itemId = await ctx.db.insert("clipboardItems", {
      pairingId: args.pairingId,
      content: args.content,
      sourceDeviceId: args.sourceDeviceId,
      type: args.type,
    });

    return itemId;
  },
});

// Mutation: Clear clipboard history for a pairing
export const clear = mutation({
  args: { pairingId: v.id("pairings") },
  handler: async (ctx, args) => {
    const items = await ctx.db
      .query("clipboardItems")
      .withIndex("by_pairing", (q) => q.eq("pairingId", args.pairingId))
      .collect();

    for (const item of items) {
      await ctx.db.delete(item._id);
    }

    return items.length;
  },
});
```

---

## 5. macOS Client Migration

### 5.1 Dependencies Update

**Remove from Package.swift / Xcode:**
- `firebase-ios-sdk`

**Add:**
- `convex-mobile` (Swift SDK)

```swift
// Package.swift or SPM
dependencies: [
    .package(url: "https://github.com/get-convex/convex-swift.git", from: "0.4.0")
]
```

### 5.2 ConvexManager.swift (Replaces FirebaseManager.swift)

```swift
//
// ConvexManager.swift
// OTPSync - Convex Backend
//

import Foundation
import ConvexMobile

class ConvexManager {
    static let shared = ConvexManager()
    let client: ConvexClient
    
    private init() {
        // Get deployment URL from config
        let deploymentUrl = Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String
            ?? "https://YOUR_DEPLOYMENT.convex.cloud"
        
        client = ConvexClient(deploymentUrl: deploymentUrl)
        
        print("✅ Convex initialized successfully")
        print("🔒 Security: E2E Encryption (No Auth Required)")
    }
    
    var isReady: Bool {
        return true
    }
}
```

### 5.3 Updated ClipboardManager.swift

**Key changes:**
- Replace `ListenerRegistration` with Convex subscription
- Replace `addDocument` with `client.mutation()`
- Replace snapshot listeners with `client.subscribe()`

```swift
// Replace Firestore listener with Convex subscription
func listenForAndroidClipboard(retryCount: Int = 0) {
    guard let pairingId = PairingManager.shared.pairingId else {
        if retryCount < 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.listenForAndroidClipboard(retryCount: retryCount + 1)
            }
        }
        return
    }
    
    stopListening()
    let macDeviceId = DeviceManager.shared.getDeviceId()
    
    isListenerActive = true
    lastListenerUpdate = Date()
    
    // Convex subscription
    Task {
        let latestClipboard = ConvexManager.shared.client.subscribe(
            to: "clipboard:getLatest",
            with: ["pairingId": pairingId],
            yielding: ClipboardItemResponse.self
        )
        .replaceError(with: nil)
        .values
        
        for await item in latestClipboard {
            guard let item = item else { continue }
            self.lastListenerUpdate = Date()
            
            if self.isSyncPaused || !self.syncToMac { continue }
            
            // Ignore own updates
            guard item.sourceDeviceId != macDeviceId else { continue }
            
            // Decrypt
            let content = self.decrypt(item.content) ?? item.content
            
            // Duplicate check
            guard content != self.lastCopiedText else { continue }
            
            await MainActor.run {
                self.ignoreNextChange = true
                self.pasteboard.clearContents()
                self.pasteboard.setString(content, forType: .string)
                self.lastCopiedText = content
                
                // Update history
                let newItem = ClipboardItem(
                    content: content,
                    timestamp: Date(),
                    deviceName: PairingManager.shared.pairedDeviceName,
                    direction: .received
                )
                self.history.insert(newItem, at: 0)
                self.lastSyncedTime = Date()
            }
        }
    }
}

// Replace Firestore upload with Convex mutation
private func uploadClipboard(text: String) {
    guard let pairingIdString = PairingManager.shared.pairingId else { return }
    let macDeviceId = DeviceManager.shared.getDeviceId()
    
    guard let encryptedContent = encrypt(text) else { return }
    
    Task {
        do {
            try await ConvexManager.shared.client.mutation(
                "clipboard:send",
                with: [
                    "pairingId": pairingIdString,
                    "content": encryptedContent,
                    "sourceDeviceId": macDeviceId,
                    "type": "text"
                ]
            )
        } catch {
            print("Error uploading clipboard: \(error)")
        }
    }
}
```

### 5.4 Updated PairingManager.swift

```swift
// Replace Firestore listener with Convex subscription
func listenForPairing(macDeviceId: String) {
    guard !isPaired else { return }
    
    listenStartTime = Date().addingTimeInterval(-3600)
    DispatchQueue.main.async { self.pairingError = nil }
    
    print("🎧 PairingManager: Start Check (MacID: \(macDeviceId))")
    
    Task {
        let pairings = ConvexManager.shared.client.subscribe(
            to: "pairings:watchForPairing",
            with: [
                "macDeviceId": macDeviceId,
                "sinceTimestamp": (listenStartTime?.timeIntervalSince1970 ?? 0) * 1000
            ],
            yielding: PairingResponse.self
        )
        .replaceError(with: nil)
        .values
        
        for await pairing in pairings {
            guard let pairing = pairing else { continue }
            
            await MainActor.run {
                self.pairingId = pairing.id
                self.pairedDeviceName = pairing.androidDeviceName
                self.isPaired = true
                self.pairingError = nil
            }
            
            UserDefaults.standard.set(pairing.id, forKey: "current_pairing_id")
            UserDefaults.standard.set(pairing.androidDeviceName, forKey: "paired_device_name")
            
            self.startMonitoringPairingStatus(pairingId: pairing.id)
            break // Exit after first valid pairing
        }
    }
}

// Unpair mutation
func unpair() {
    guard let pairingId = pairingId else { return }
    
    Task {
        do {
            try await ConvexManager.shared.client.mutation(
                "pairings:remove",
                with: ["pairingId": pairingId]
            )
        } catch {
            print("Error removing pairing: \(error)")
        }
    }
    
    // Clear local state...
}
```

### 5.5 Swift Response Models

```swift
// Models for Convex responses
struct ClipboardItemResponse: Decodable {
    let _id: String
    let _creationTime: Double
    let content: String
    let pairingId: String
    let sourceDeviceId: String
    let type: String
}

struct PairingResponse: Decodable {
    let _id: String
    let _creationTime: Double
    let androidDeviceId: String
    let androidDeviceName: String
    let macDeviceId: String
    let macDeviceName: String
    let status: String
    let createdAt: Double
    
    var id: String { _id }
}
```

---

## 6. Android Client Migration

### 6.1 Dependencies Update

**Remove from build.gradle.kts:**
```kotlin
// Remove Firebase
implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
implementation("com.google.firebase:firebase-auth-ktx")
implementation("com.google.firebase:firebase-firestore-ktx")
implementation("com.google.firebase:firebase-storage-ktx")
implementation("com.google.firebase:firebase-messaging-ktx")
```

**Add:**
```kotlin
// Add Convex
plugins {
    kotlin("plugin.serialization") version "1.9.0"
}

dependencies {
    implementation("dev.convex:android-convexmobile:0.4.1@aar") {
        isTransitive = true
    }
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
}
```

### 6.2 ConvexManager.kt (Replaces FirestoreManager.kt)

```kotlin
package com.bunty.clipsync

import android.content.Context
import android.util.Log
import dev.convex.android.ConvexClient
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.Serializable

object ConvexManager {
    private var client: ConvexClient? = null
    
    fun getClient(context: Context): ConvexClient {
        if (client == null) {
            val url = context.getString(R.string.convex_url)
            client = ConvexClient(url)
            Log.d("ConvexManager", "Convex client initialized")
        }
        return client!!
    }

    // --- Encryption Helpers (unchanged from FirestoreManager) ---
    private fun getSharedSecret(context: Context): String {
        return DeviceManager.getEncryptionKey(context)
    }

    fun decryptData(context: Context, encryptedBase64: String): String {
        // Same implementation as before
        try {
            val encryptedBytes = android.util.Base64.decode(encryptedBase64, android.util.Base64.NO_WRAP)
            if (encryptedBytes.size < 28) return ""

            val keyBytes = hexStringToByteArray(getSharedSecret(context))
            val keySpec = javax.crypto.spec.SecretKeySpec(keyBytes, "AES")

            val iv = encryptedBytes.copyOfRange(0, 12)
            val ciphertext = encryptedBytes.copyOfRange(12, encryptedBytes.size)

            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            val gcmSpec = javax.crypto.spec.GCMParameterSpec(128, iv)

            cipher.init(javax.crypto.Cipher.DECRYPT_MODE, keySpec, gcmSpec)
            val plaintextBytes = cipher.doFinal(ciphertext)

            return String(plaintextBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            throw e
        }
    }

    fun encryptData(context: Context, plainText: String): String {
        // Same implementation as before
        try {
            val keyBytes = hexStringToByteArray(getSharedSecret(context))
            val keySpec = javax.crypto.spec.SecretKeySpec(keyBytes, "AES")

            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            val iv = ByteArray(12)
            java.security.SecureRandom().nextBytes(iv)
            
            val gcmSpec = javax.crypto.spec.GCMParameterSpec(128, iv)
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, keySpec, gcmSpec)

            val ciphertext = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))

            val combined = ByteArray(iv.size + ciphertext.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)

            return android.util.Base64.encodeToString(combined, android.util.Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("ConvexManager", "Encryption failed", e)
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

    // --- QR Parsing (unchanged) ---
    fun parseQRData(qrData: String): Map<String, Any>? {
        // Same implementation as before
        try {
            if (qrData.trim().startsWith("{")) {
                val jsonObject = org.json.JSONObject(qrData)
                val macId = jsonObject.optString("macId")
                val deviceName = jsonObject.optString("deviceName").ifEmpty {
                    jsonObject.optString("macDeviceName", "Mac")
                }
                val secret = jsonObject.optString("secret")

                if (macId.isNotEmpty()) {
                    return mapOf(
                        "macDeviceId" to macId,
                        "macDeviceName" to deviceName,
                        "serverRegion" to jsonObject.optString("server").ifEmpty {
                            jsonObject.optString("serverRegion", "IN")
                        },
                        "secret" to secret
                    )
                }
            }
            return null
        } catch (e: Exception) {
            return null
        }
    }

    // --- Convex Operations ---

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

        // Save encryption key
        if (!secret.isNullOrEmpty()) {
            DeviceManager.saveEncryptionKey(context, secret)
            Log.d("ConvexManager", "Secure Key Swapped & Saved")
        }

        try {
            val pairingId = getClient(context).mutation<String>(
                "pairings:create",
                args = mapOf(
                    "androidDeviceId" to androidDeviceId,
                    "androidDeviceName" to androidDeviceName,
                    "macDeviceId" to macDeviceId,
                    "macDeviceName" to macDeviceName
                )
            )

            DeviceManager.savePairing(
                context = context,
                pairingId = pairingId,
                macDeviceId = macDeviceId,
                macDeviceName = macDeviceName
            )

            onSuccess(pairingId)
        } catch (e: Exception) {
            Log.e("ConvexManager", "Failed to create pairing", e)
            onFailure(e)
        }
    }

    fun listenToClipboard(
        context: Context,
        onClipboardUpdate: (String) -> Unit
    ): Flow<Result<ClipboardItem?>> {
        val pairingId = DeviceManager.getPairingId(context) ?: return kotlinx.coroutines.flow.emptyFlow()
        val currentDeviceId = DeviceManager.getDeviceId(context)

        return getClient(context).subscribe<ClipboardItem?>(
            "clipboard:getLatest",
            args = mapOf("pairingId" to pairingId)
        )
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
            getClient(context).mutation<String>(
                "clipboard:send",
                args = mapOf(
                    "pairingId" to pairingId,
                    "content" to encryptedContent,
                    "sourceDeviceId" to deviceId,
                    "type" to "text"
                )
            )
            Log.d("ConvexManager", "Clipboard sent successfully (Encrypted)")
            onSuccess()
        } catch (e: Exception) {
            Log.e("ConvexManager", "Failed to send clipboard", e)
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
            getClient(context).mutation<Unit>(
                "pairings:remove",
                args = mapOf("pairingId" to pairingId)
            )
            Log.d("ConvexManager", "Pairing cleared")
            DeviceManager.clearPairing(context)
            onSuccess()
        } catch (e: Exception) {
            Log.e("ConvexManager", "Failed to clear pairing", e)
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
            val deletedCount = getClient(context).mutation<Int>(
                "clipboard:clear",
                args = mapOf("pairingId" to pairingId)
            )
            Log.d("ConvexManager", "Cleared $deletedCount clipboard items")
            onSuccess()
        } catch (e: Exception) {
            Log.e("ConvexManager", "Failed to clear clipboard", e)
            onFailure(e)
        }
    }
}

// Data classes
@Serializable
data class ClipboardItem(
    val _id: String,
    val _creationTime: Long,
    val content: String,
    val pairingId: String,
    val sourceDeviceId: String,
    val type: String
)

@Serializable
data class Pairing(
    val _id: String,
    val _creationTime: Long,
    val androidDeviceId: String,
    val androidDeviceName: String,
    val macDeviceId: String,
    val macDeviceName: String,
    val status: String,
    val createdAt: Long
)
```

### 6.3 Resource Strings

Add to `res/values/strings.xml`:
```xml
<string name="convex_url">https://YOUR_DEPLOYMENT.convex.cloud</string>
```

For build variants, in `build.gradle.kts`:
```kotlin
buildTypes {
    release {
        resValue("string", "convex_url", "https://YOUR_PROD.convex.cloud")
    }
    debug {
        resValue("string", "convex_url", "https://YOUR_DEV.convex.cloud")
    }
}
```

### 6.4 Remove Firebase from AndroidManifest.xml

Remove:
```xml
<!-- Remove Firebase-related meta-data and services -->
<meta-data
    android:name="firebase_analytics_collection_enabled"
    android:value="false" />
    
<service
    android:name=".MyFirebaseMessagingService"
    android:exported="false">
    ...
</service>
```

---

## 7. Security Considerations

### 7.1 Encryption Preservation

The end-to-end encryption model remains **unchanged**:

1. **Encryption Key** - Generated on Mac, exchanged via QR code
2. **Algorithm** - AES-256-GCM (authenticated encryption)
3. **Client-side only** - Convex never sees plaintext data
4. **Key format** - 64-character hex string (256 bits)

### 7.2 Transport Security

| Layer | Firebase | Convex |
|-------|----------|--------|
| TLS | Yes | Yes |
| Certificate Pinning | Optional | Optional |
| WebSocket Security | N/A | WSS |

### 7.3 Access Control

Currently using **no authentication** (security through encryption + pairing ID).

Future consideration: Add Convex's built-in auth for additional layer.

---

## 8. Migration Strategy

### 8.1 Phase 1: Backend Setup (Day 1)

1. Create Convex account and project
2. Implement and deploy Convex functions
3. Test with Convex dashboard

### 8.2 Phase 2: macOS Client (Day 2-3)

1. Add Convex Swift SDK
2. Create `ConvexManager.swift`
3. Update `ClipboardManager.swift`
4. Update `PairingManager.swift`
5. Update QR code generation
6. Test pairing flow
7. Test clipboard sync

### 8.3 Phase 3: Android Client (Day 4-5)

1. Remove Firebase dependencies
2. Add Convex Android SDK
3. Create `ConvexManager.kt`
4. Update all Firebase references
5. Update `Homescreen.kt`
6. Update `ClipboardAccessibilityService.kt`
7. Test complete flow

### 8.4 Phase 4: Testing & Cleanup (Day 6-7)

1. Integration testing
2. Performance testing
3. Remove Firebase configuration files
4. Update documentation
5. Release

### 8.5 Rollback Plan

If critical issues are found:
1. Revert to Firebase branch
2. Firebase remains functional (no data migration needed)
3. Address issues, retry migration

---

## 9. Testing Plan

### 9.1 Unit Tests

| Component | Test Cases |
|-----------|------------|
| Encryption | Encrypt/decrypt roundtrip |
| QR Parsing | Valid JSON, legacy format |
| Convex Client | Connection, error handling |

### 9.2 Integration Tests

| Flow | Steps |
|------|-------|
| Pairing | Mac shows QR → Android scans → Both paired |
| Mac→Android | Copy on Mac → Appears on Android |
| Android→Mac | Copy on Android → Appears on Mac |
| Unpair | Either device unpairs → Both disconnected |

### 9.3 Edge Cases

- Network interruption during sync
- App backgrounded/suspended
- Device sleep/wake cycle
- Large clipboard content (>1MB)
- Rapid successive copies

---

## 10. Manual Testing Instructions

### Prerequisites

Before testing, ensure:
- [ ] Convex backend is deployed (`npx convex deploy`)
- [ ] macOS app is built with new Convex SDK
- [ ] Android app is built with new Convex SDK
- [ ] Both apps point to same Convex deployment URL

### Test 1: Initial Pairing

**macOS:**
1. Launch OTPSync on Mac
2. Verify the landing/pairing screen appears
3. Confirm QR code is displayed
4. Note the QR code contains JSON with `macId`, `deviceName`, and `secret`

**Android:**
1. Launch OTPSync on Android
2. Grant required permissions (Accessibility, etc.)
3. Tap "Scan QR Code"
4. Scan the QR code from Mac

**Expected Results:**
- [ ] Android shows "Connected to [Mac Name]"
- [ ] Mac transitions to Connected screen
- [ ] Mac shows "Connected to [Android Name]"

### Test 2: Mac to Android Clipboard Sync

**macOS:**
1. Ensure "Sync from Mac" toggle is ON in settings
2. Open any app (e.g., Notes, TextEdit)
3. Type: `Test from Mac - [timestamp]`
4. Select text and press ⌘C to copy

**Android:**
1. Ensure "Sync to Mac" toggle is ON
2. Wait 1-2 seconds

**Expected Results:**
- [ ] Android notification appears with clipboard content
- [ ] Pasting on Android shows the Mac text
- [ ] OTPSync history shows the synced item

### Test 3: Android to Mac Clipboard Sync

**Android:**
1. Ensure "Sync to Mac" toggle is ON
2. Open any app with text
3. Long-press and copy text: `Test from Android - [timestamp]`

**macOS:**
1. Ensure "Sync to Mac" toggle is ON
2. Wait 1-2 seconds
3. Press ⌘V to paste

**Expected Results:**
- [ ] Pasted text matches Android clipboard
- [ ] OTPSync menubar shows sync activity
- [ ] History updated

### Test 4: Encryption Verification

**Using Convex Dashboard:**
1. Open Convex Dashboard → Data → clipboardItems
2. Find the most recent clipboard item
3. Inspect the `content` field

**Expected Results:**
- [ ] Content is Base64 encoded (not plaintext)
- [ ] Cannot read actual clipboard content in dashboard
- [ ] Content starts with random characters (IV)

### Test 5: Real-time Sync Performance

**Both Devices:**
1. Copy text rapidly (5 times within 10 seconds)
2. Alternate between devices

**Expected Results:**
- [ ] All items sync within 2 seconds each
- [ ] No duplicates in history
- [ ] No missed items

### Test 6: Offline/Reconnection

**macOS:**
1. Disable Wi-Fi
2. Copy text on Android
3. Re-enable Wi-Fi

**Expected Results:**
- [ ] Mac reconnects automatically
- [ ] Pending clipboard syncs after reconnection
- [ ] No crash or error dialogs

### Test 7: Unpair Flow

**Android:**
1. Open OTPSync settings
2. Tap "Unpair" or "Disconnect"

**Expected Results:**
- [ ] Android returns to QR scan screen
- [ ] Mac returns to QR code display
- [ ] Convex Dashboard shows pairing deleted
- [ ] Clipboard history cleared

### Test 8: App Restart Persistence

**Both Devices:**
1. Pair devices successfully
2. Force quit both apps
3. Relaunch both apps

**Expected Results:**
- [ ] Both apps remember pairing state
- [ ] Connected screen shows on both
- [ ] Clipboard sync resumes automatically

### Test 9: Background Sync (Android)

**Android:**
1. Pair devices
2. Minimize OTPSync (don't kill)
3. Copy text on Mac

**Expected Results:**
- [ ] Android receives notification
- [ ] Clipboard synced in background
- [ ] No need to open app

### Test 10: Large Content Sync

**macOS:**
1. Copy a large text block (10,000+ characters)
2. Sync to Android

**Expected Results:**
- [ ] Full content syncs successfully
- [ ] No truncation
- [ ] Reasonable sync time (<5 seconds)

---

## Appendix A: File Changes Summary

### Files to DELETE (macOS)

- `mac/ClipSync/FirebaseManager.swift`
- `mac/ClipSync/GoogleService-Info.plist` (if exists)

### Files to CREATE (macOS)

- `mac/ClipSync/ConvexManager.swift`
- `mac/ClipSync/ConvexModels.swift`

### Files to MODIFY (macOS)

- `mac/ClipSync/ClipboardManager.swift`
- `mac/ClipSync/PairingManager.swift`
- `mac/ClipSync/QRGen.swift` (update URL in QR if needed)
- `mac/ClipSync.xcodeproj/project.pbxproj` (dependencies)

### Files to DELETE (Android)

- `android/app/src/main/java/com/bunty/clipsync/FirestoreManager.kt`
- `android/app/src/main/java/com/bunty/clipsync/MyFirebaseMessagingService.kt`
- `android/app/google-services.json` (if exists)

### Files to CREATE (Android)

- `android/app/src/main/java/com/bunty/clipsync/ConvexManager.kt`

### Files to MODIFY (Android)

- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/com/bunty/clipsync/Homescreen.kt`
- `android/app/src/main/java/com/bunty/clipsync/ClipboardAccessibilityService.kt`
- `android/app/src/main/java/com/bunty/clipsync/ClipSyncApp.kt`

### Files to CREATE (Backend)

- `convex/schema.ts`
- `convex/pairings.ts`
- `convex/clipboard.ts`
- `convex/tsconfig.json`
- `package.json`

---

## Appendix B: Convex Dashboard Verification

After deployment, verify in Convex Dashboard:

1. **Functions Tab:**
   - `pairings:get`
   - `pairings:getByMacId`
   - `pairings:watchForPairing`
   - `pairings:create`
   - `pairings:remove`
   - `clipboard:getLatest`
   - `clipboard:getHistory`
   - `clipboard:send`
   - `clipboard:clear`

2. **Data Tab:**
   - `pairings` table with proper schema
   - `clipboardItems` table with proper schema
   - Indexes visible and active

3. **Logs Tab:**
   - Function invocations visible
   - No errors during normal operation

---

## Appendix C: Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Convex URL not found" | Missing config | Add URL to Info.plist (Mac) or strings.xml (Android) |
| Pairing not detected | Query timing | Check `sinceTimestamp` calculation |
| Clipboard not syncing | Encryption mismatch | Verify same secret on both devices |
| Subscription not updating | Stale connection | Implement reconnection logic |
| "Function not found" | Not deployed | Run `npx convex deploy` |

---

*End of Specification Document*
