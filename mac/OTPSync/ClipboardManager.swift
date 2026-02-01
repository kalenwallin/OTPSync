//
// ClipboardManager.swift
// OTPSync - Convex Backend
//

import AppKit
import Combine
import CryptoKit
import Foundation

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var history: [ClipboardItem] = []
    @Published var isSyncPaused: Bool = false
    @Published var lastSyncedTime: Date?

    // Sync Statistics
    @Published var syncCountToday: Int = 0
    @Published var syncCountSession: Int = 0
    @Published var syncCountAllTime: Int = 0
    @Published var sentCount: Int = 0
    @Published var receivedCount: Int = 0
    @Published var syncStreak: Int = 0

    private let syncStatsKey = "syncStats"
    private var sessionStartDate: Date = Date()

    var syncToMac: Bool {
        UserDefaults.standard.bool(forKey: "syncToMac")
    }
    var syncFromMac: Bool {
        UserDefaults.standard.bool(forKey: "syncFromMac")
    }

    private let pasteboard = NSPasteboard.general
    private var timer: DispatchSourceTimer?  // Changed from Timer to DispatchSourceTimer
    private var watchdogTimer: Timer?  // Fix for infinite timer loop
    private var lastChangeCount = 0
    private var lastCopiedText: String = ""
    private var ignoreNextChange = false

    // Convex subscription
    private var clipboardSubscription: AnyCancellable?
    private var lastReceivedItemId: String = ""

    private var sharedSecretHex: String {
        return UserDefaults.standard.string(forKey: "encryption_key")
            ?? Secrets.fallbackEncryptionKey
    }

    private var isListenerActive = false
    private var lastListenerUpdate = Date()

    init() {
        loadSyncStats()
    }

    // --- Monitoring Strategy (Poller) ---
    // Uses DispatchSourceTimer on a background queue to poll NSPasteboard changeCount.
    // This avoids main thread blocking and "App Nap" suspension issues.
    func startMonitoring() {
        if isSyncPaused { return }
        stopMonitoring()

        lastChangeCount = pasteboard.changeCount

        let queue = DispatchQueue(label: "com.otpsync.clipboard.monitor", qos: .userInitiated)
        let newTimer = DispatchSource.makeTimerSource(queue: queue)

        // Poll every 300ms
        newTimer.schedule(
            deadline: .now(), repeating: .milliseconds(300), leeway: .milliseconds(50))

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

        // Dispatch to main queue to avoid race condition with ignoreNextChange flag
        // which is set from the main queue when receiving clipboard from Android
        DispatchQueue.main.async { [weak self] in
            self?.processClipboardChange()
        }
    }

    private func processClipboardChange() {
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
        self.incrementSyncCount(direction: .sent)
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
                        "type": "text",
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

                let deviceName = PairingManager.shared.pairedDeviceName

                // Send macOS notification
                NotificationManager.shared.sendClipboardSyncNotification(
                    content: content,
                    deviceName: deviceName
                )

                // History Update (UI)
                if let lastItem = self.history.first, lastItem.content == content { return }

                let newItem = ClipboardItem(
                    content: content,
                    timestamp: Date(),
                    deviceName: deviceName,
                    direction: .received
                )
                self.history.insert(newItem, at: 0)
                self.lastSyncedTime = Date()
                self.incrementSyncCount(direction: .received)
            }
        )

        startListenerWatchdog()
    }

    // --- Watchdog ---
    // Restarts listener if no heartbeat for 60s (Fixes stale connection issues)
    private func startListenerWatchdog() {
        watchdogTimer?.invalidate()

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) {
            [weak self] timer in
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

    // MARK: - Sync Statistics

    func loadSyncStats() {
        let defaults = UserDefaults.standard
        syncCountAllTime = defaults.integer(forKey: "\(syncStatsKey)_allTime")
        sentCount = defaults.integer(forKey: "\(syncStatsKey)_sent")
        receivedCount = defaults.integer(forKey: "\(syncStatsKey)_received")

        // Check if today's date matches stored date
        let storedDateString = defaults.string(forKey: "\(syncStatsKey)_todayDate") ?? ""
        let todayString = formatDateString(Date())

        if storedDateString == todayString {
            syncCountToday = defaults.integer(forKey: "\(syncStatsKey)_today")
        } else {
            // Reset daily count for new day
            syncCountToday = 0
            defaults.set(todayString, forKey: "\(syncStatsKey)_todayDate")
            defaults.set(0, forKey: "\(syncStatsKey)_today")
        }

        // Calculate sync streak
        syncStreak = calculateSyncStreak(defaults: defaults, todayString: todayString)

        sessionStartDate = Date()
        syncCountSession = 0
    }

    private func calculateSyncStreak(defaults: UserDefaults, todayString: String) -> Int {
        var streakDates = defaults.stringArray(forKey: "\(syncStatsKey)_streakDates") ?? []

        // If no dates yet, streak is 0
        guard !streakDates.isEmpty else { return 0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // Sort dates in descending order (most recent first)
        streakDates.sort { $0 > $1 }

        var streak = 0
        var expectedDate = Date()

        // If today isn't in the list yet, start checking from yesterday
        if streakDates.first != todayString {
            expectedDate =
                Calendar.current.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
        }

        for dateString in streakDates {
            let expectedDateString = formatDateString(expectedDate)

            if dateString == expectedDateString {
                streak += 1
                expectedDate =
                    Calendar.current.date(byAdding: .day, value: -1, to: expectedDate)
                    ?? expectedDate
            } else if dateString < expectedDateString {
                // Gap in dates, streak is broken
                break
            }
            // If dateString > expectedDateString, skip (future date edge case)
        }

        return streak
    }

    func incrementSyncCount(direction: ClipboardDirection) {
        DispatchQueue.main.async {
            self.syncCountToday += 1
            self.syncCountSession += 1
            self.syncCountAllTime += 1

            switch direction {
            case .sent:
                self.sentCount += 1
            case .received:
                self.receivedCount += 1
            }

            self.saveSyncStats()
        }
    }

    private func saveSyncStats() {
        let defaults = UserDefaults.standard
        defaults.set(syncCountAllTime, forKey: "\(syncStatsKey)_allTime")
        defaults.set(syncCountToday, forKey: "\(syncStatsKey)_today")
        defaults.set(sentCount, forKey: "\(syncStatsKey)_sent")
        defaults.set(receivedCount, forKey: "\(syncStatsKey)_received")

        let todayString = formatDateString(Date())
        defaults.set(todayString, forKey: "\(syncStatsKey)_todayDate")

        // Update streak dates
        var streakDates = defaults.stringArray(forKey: "\(syncStatsKey)_streakDates") ?? []
        if !streakDates.contains(todayString) {
            streakDates.append(todayString)
            // Keep only last 365 days to prevent unbounded growth
            if streakDates.count > 365 {
                streakDates = Array(streakDates.suffix(365))
            }
            defaults.set(streakDates, forKey: "\(syncStatsKey)_streakDates")
            // Recalculate streak
            syncStreak = calculateSyncStreak(defaults: defaults, todayString: todayString)
        }
    }

    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
