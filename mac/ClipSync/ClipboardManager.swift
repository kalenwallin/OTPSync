//
// ClipboardManager.swift
// ClipSync - Convex Backend
//

import Foundation
import AppKit
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
    private var watchdogTimer: Timer? // Fix for infinite timer loop
    private var lastChangeCount = 0
    private var lastCopiedText: String = ""
    private var ignoreNextChange = false
    
    // Convex subscription
    private var clipboardSubscription: AnyCancellable?
    private var lastReceivedItemId: String = ""
    
    private var sharedSecretHex: String {
        return UserDefaults.standard.string(forKey: "encryption_key") ?? Secrets.fallbackEncryptionKey
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
        } else {
            startMonitoring()
            listenForAndroidClipboard()
        }
    }
    
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
    // Encrypts text using AES-GCM (Shared Key) and pushes to Convex
    private func uploadClipboard(text: String) {
        guard let pairingId = PairingManager.shared.pairingId else { return }
        let macDeviceId = DeviceManager.shared.getDeviceId()
        
        guard let encryptedContent = encrypt(text) else { return }
        
        Task {
            do {
                let _: String = try await ConvexManager.shared.mutation(
                    "clipboard:send",
                    args: [
                        "pairingId": pairingId,
                        "content": encryptedContent,
                        "sourceDeviceId": macDeviceId,
                        "type": "text"
                    ]
                )
                print("✅ Clipboard uploaded to Convex")
            } catch {
                print("❌ Error uploading clipboard: \(error)")
            }
        }
    }
    
    // --- Download Logic ---
    // Polling-based listener for incoming clipboard changes from Android
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
        
        // Use Convex polling subscription
        clipboardSubscription = ConvexManager.shared.subscribe(
            to: "clipboard:getLatest",
            args: ["pairingId": pairingId],
            interval: 0.5,
            type: ConvexClipboardItem.self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    print("❌ Clipboard subscription error: \(error)")
                    // Retry on error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.listenForAndroidClipboard()
                    }
                }
            },
            receiveValue: { [weak self] item in
                guard let self = self else { return }
                self.lastListenerUpdate = Date()
                
                if self.isSyncPaused || !self.syncToMac { return }
                
                guard let item = item else { return }
                
                // Ignore if we already processed this item
                guard item.documentId != self.lastReceivedItemId else { return }
                
                // Ignore own updates
                guard item.sourceDeviceId != macDeviceId else { return }
                
                self.lastReceivedItemId = item.documentId
                
                // DECRYPT
                let content = self.decrypt(item.content) ?? item.content
                
                // Duplicate Check
                guard content != self.lastCopiedText else { return }
                
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
        )
        
        startListenerWatchdog()
    }

    // --- Watchdog ---
    // Restarts listener if no heartbeat for 60s (Fixes stale connection issues)
    private func startListenerWatchdog() {
        watchdogTimer?.invalidate()
        
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self = self else { 
                timer.invalidate() 
                return 
            }
            
            if !self.isListenerActive {
                timer.invalidate()
                return
            }
            
            if Date().timeIntervalSince(self.lastListenerUpdate) > 60 {
                print("⚠️ Watchdog: Listener stale. Restarting...")
                self.listenForAndroidClipboard()
            }
        }
    }
    
    func stopListening() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        clipboardSubscription?.cancel()
        clipboardSubscription = nil
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


