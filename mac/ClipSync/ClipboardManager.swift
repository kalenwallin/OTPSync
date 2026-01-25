//
// ClipboardManager.swift
// ClipSync - Fixed Timer Suspension Issue
//

import Foundation
import AppKit
import FirebaseFirestore
import Combine
import CryptoKit

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var history: [ClipboardItem] = []
    @Published var isSyncPaused: Bool = false
    @Published var lastSyncedTime: Date?
    
    var syncToMac: Bool {
        UserDefaults.standard.bool(forKey: "syncToMac")
    }
    var syncFromMac: Bool {
        UserDefaults.standard.bool(forKey: "syncFromMac")
    }
    
    private let pasteboard = NSPasteboard.general
    private var timer: DispatchSourceTimer? // Changed from Timer to DispatchSourceTimer
    private var lastChangeCount = 0
    private var lastCopiedText: String = ""
    private var ignoreNextChange = false
    private let db = FirebaseManager.shared.db
    private var clipboardListener: ListenerRegistration?
    
    private var sharedSecretHex: String {
        return UserDefaults.standard.string(forKey: "encryption_key") ?? "5D41402ABC4B2A76B9719D911017C59228B4637452F80776313460C451152033"
    }
    
    private var isListenerActive = false
    private var lastListenerUpdate = Date()
    
    // --- Monitoring Strategy (Poller) ---
    // Uses DispatchSourceTimer on a background queue to poll NSPasteboard changeCount.
    // This avoids main thread blocking and "App Nap" suspension issues.
    func startMonitoring() {
        if isSyncPaused { return }
        stopMonitoring()
        
        lastChangeCount = pasteboard.changeCount
        
        let queue = DispatchQueue(label: "com.clipsync.clipboard.monitor", qos: .userInitiated)
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        
        // Poll every 300ms
        newTimer.schedule(deadline: .now(), repeating: .milliseconds(300), leeway: .milliseconds(50))
        
        newTimer.setEventHandler { [weak self] in
            self?.checkClipboard()
        }
        
        newTimer.resume()
        timer = newTimer
    }
    
    func toggleSync() {
        isSyncPaused.toggle()
        if isSyncPaused {
            stopMonitoring()
            stopListening()
        isSyncPaused.toggle()
        if isSyncPaused {
            stopMonitoring()
            stopListening()
        } else {
            startMonitoring()
            listenForAndroidClipboard()
        }
    }
    
    func pullClipboard() {
    func pullClipboard() {

        stopListening()
        listenForAndroidClipboard()
    }
    
    func clearHistory() {
        history.removeAll()
    }
    
    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        timer?.cancel()
        timer = nil
    }
    
    private func checkClipboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        if ignoreNextChange {
            ignoreNextChange = false
            return
        }
        
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }
        
        guard text != lastCopiedText else { return }
        lastCopiedText = text
        
        lastCopiedText = text
        
        guard syncFromMac else {
            return
        }
        
        uploadClipboard(text: text)
        
        DispatchQueue.main.async {
            if let lastItem = self.history.first, lastItem.content == text {
                return
            }
            
            let newItem = ClipboardItem(
                content: text,
                timestamp: Date(),
                deviceName: "Mac",
                direction: .sent
            )
            self.history.insert(newItem, at: 0)
            self.lastSyncedTime = Date()
        }
    }
    
    // --- Upload Logic ---
    // Encrypts text using AES-GCM (Shared Key) and pushes to Firestore
    private func uploadClipboard(text: String) {
        guard let pairingId = PairingManager.shared.pairingId else { return }
        let macDeviceId = DeviceManager.shared.getDeviceId()
        
        guard let encryptedContent = encrypt(text) else {
        guard let encryptedContent = encrypt(text) else {
            return
        }
        
        let clipboardData: [String: Any] = [
            "content": encryptedContent,
            "timestamp": FieldValue.serverTimestamp(),
            "pairingId": pairingId,
            "sourceDeviceId": macDeviceId,
            "type": "text"
        ]
        
        db.collection("clipboardItems").addDocument(data: clipboardData) { error in
        db.collection("clipboardItems").addDocument(data: clipboardData) { error in
            if let error = error {
                // Handle upload error if needed
            }
        }
    }
    
    // --- Download Logic ---
    // Real-time listener for incoming clipboard changes from Android
    func listenForAndroidClipboard(retryCount: Int = 0) {
        guard let pairingId = PairingManager.shared.pairingId else {
            // Retry logic for startup race conditions
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
        
        clipboardListener = db.collection("clipboardItems")
            .whereField("pairingId", isEqualTo: pairingId)
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
                guard let self = self else { return }
                self.lastListenerUpdate = Date()
                
                if self.isSyncPaused || !self.syncToMac { return }
                
                if error != nil {
                     // Retry on temporary network/permission fail
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.listenForAndroidClipboard()
                    }
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else { return }
                let doc = documents[0].data()
                
                // Content Filter: Ignore own updates
                guard let encryptedContent = doc["content"] as? String,
                      let sourceDeviceId = doc["sourceDeviceId"] as? String,
                      sourceDeviceId != macDeviceId else { return }
                
                // DECRYPT
                let content = self.decrypt(encryptedContent) ?? encryptedContent
                
                // Duplicate Check
                guard content != self.lastCopiedText else { return }

                DispatchQueue.main.async {
                    self.ignoreNextChange = true
                    self.pasteboard.clearContents()
                    self.pasteboard.setString(content, forType: .string)
                    self.lastCopiedText = content
                    
                    // History Update (UI)
                    if let lastItem = self.history.first, lastItem.content == content { return }
                    
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
        
        startListenerWatchdog()
    }

    // --- Watchdog ---
    // Restarts listener if no heartbeat for 60s (Fixes stale connection issues)
    private func startListenerWatchdog() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isListenerActive else {
                timer.invalidate()
                return
            }
            
            if Date().timeIntervalSince(self.lastListenerUpdate) > 60 {
                self.listenForAndroidClipboard()
            }
        }
    }
    
    func stopListening() {
        clipboardListener?.remove()
        clipboardListener = nil
        isListenerActive = false
    }
    
    // --- Crypto Helpers (AES-GCM) ---
    private func encrypt(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        
        do {
            let keyData = hexToData(hex: sharedSecretHex)
            let key = SymmetricKey(data: keyData)
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined?.base64EncodedString()
        } catch {
            return nil
        }
    }
    
    private func decrypt(_ base64String: String) -> String? {
        guard let data = Data(base64Encoded: base64String) else { return nil }
        
        do {
            let keyData = hexToData(hex: sharedSecretHex)
            let key = SymmetricKey(data: keyData)
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    private func hexToData(hex: String) -> Data {
        var data = Data()
        var temp = ""
        for char in hex {
            temp.append(char)
            if temp.count == 2 {
                if let byte = UInt8(temp, radix: 16) {
                    data.append(byte)
                }
                temp = ""
            }
        }
        return data
    }
}

