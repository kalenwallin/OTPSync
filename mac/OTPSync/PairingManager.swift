//
// PairingManager.swift
// OTPSync - Convex Backend
//

import Combine
import Foundation

class PairingManager: ObservableObject {
    static let shared = PairingManager()

    @Published var isPaired: Bool =
        UserDefaults.standard.string(forKey: "current_pairing_id") != nil
    @Published var pairedDeviceName: String =
        UserDefaults.standard.string(forKey: "paired_device_name") ?? ""
    @Published var pairingId: String? = UserDefaults.standard.string(forKey: "current_pairing_id")
    @Published var isSetupComplete: Bool = UserDefaults.standard.bool(forKey: "is_setup_complete")
    @Published var pairingError: String? = nil

    // Convex subscriptions
    private var pairingSubscription: AnyCancellable?
    private var unpairingSubscription: AnyCancellable?
    private var listenStartTime: Date?
    private var pairingPollTask: Task<Void, Never>?

    // --- Pairing Handshake ---
    // Subscribes to Convex for a new pairing with matching macId
    func listenForPairing(macDeviceId: String) {
        guard !isPaired else { return }

        // Time window: Relaxed to 1 hour to account for clock skew/restarts
        listenStartTime = Date().addingTimeInterval(-3600)

        DispatchQueue.main.async { self.pairingError = nil }

        print("🎧 PairingManager: Start Check (MacID: \(macDeviceId))")

        startConvexPairingListener(macDeviceId: macDeviceId)
        startHTTPPairingPoller(macDeviceId: macDeviceId)
    }

    // HTTP polling fallback — queries Convex directly every 2s so pairing works
    // even if the WebSocket subscription has protocol issues.
    private func startHTTPPairingPoller(macDeviceId: String) {
        pairingPollTask?.cancel()
        let sinceTimestamp = (listenStartTime?.timeIntervalSince1970 ?? 0) * 1000

        pairingPollTask = Task {
            while !Task.isCancelled {
                do {
                    let pairing: ConvexPairing? = try await ConvexManager.shared.query(
                        "pairings:watchForPairing",
                        args: [
                            "macDeviceId": macDeviceId,
                            "sinceTimestamp": sinceTimestamp,
                        ]
                    )
                    if let pairing = pairing, !self.isPaired {
                        print("✅ HTTP Poll found pairing! (ID: \(pairing.documentId))")
                        await MainActor.run { self.processPairingData(pairing) }
                        return
                    }
                } catch {
                    print("⚠️ PairingManager HTTP poll error: \(error.localizedDescription)")
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func startConvexPairingListener(macDeviceId: String) {
        let sinceTimestamp = (listenStartTime?.timeIntervalSince1970 ?? 0) * 1000

        pairingSubscription = ConvexManager.shared.subscribe(
            to: "pairings:watchForPairing",
            args: [
                "macDeviceId": macDeviceId,
                "sinceTimestamp": sinceTimestamp,
            ],
            type: ConvexPairing.self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    print("❌ Pairing subscription error: \(error)")
                    self?.pairingError = "Connection error. Check network."
                }
            },
            receiveValue: { [weak self] optionalPairing in
                guard let self = self, let pairing = optionalPairing else { return }

                // Found a valid pairing!
                print("✅ WS Pairing Found! (ID: \(pairing.documentId))")

                self.processPairingData(pairing)
            }
        )
    }

    private func processPairingData(_ pairing: ConvexPairing) {
        // Save State (Memory)
        DispatchQueue.main.async {
            self.pairingId = pairing.documentId
            self.pairedDeviceName = pairing.androidDeviceName
            self.isPaired = true
            self.pairingError = nil
        }

        // Persistence (Disk)
        UserDefaults.standard.set(pairing.documentId, forKey: "current_pairing_id")
        UserDefaults.standard.set(pairing.androidDeviceName, forKey: "paired_device_name")

        // Start Unpair Watcher
        self.startMonitoringPairingStatus(pairingId: pairing.documentId)

        // Cleanup Listener
        self.pairingSubscription?.cancel()
        self.pairingSubscription = nil
        self.pairingPollTask?.cancel()
        self.pairingPollTask = nil
    }

    // --- Persistence & Restoration ---

    // Monitors for remote unpair (deletion of document)
    func startMonitoringPairingStatus(pairingId: String) {
        unpairingSubscription?.cancel()

        unpairingSubscription = ConvexManager.shared.subscribe(
            to: "pairings:exists",
            args: ["pairingId": pairingId],
            type: Bool.self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { _ in },
            receiveValue: { [weak self] exists in
                guard let self = self else { return }

                // If pairing no longer exists, unpair locally
                if let exists = exists, !exists {
                    print("⚠️ Pairing deleted remotely, unpairing...")
                    self.unpair()
                }
            }
        )
    }

    // Stop listening
    func stopListening() {
        pairingSubscription?.cancel()
        pairingSubscription = nil
        pairingPollTask?.cancel()
        pairingPollTask = nil
        listenStartTime = nil
    }

    // Unpair device
    func unpair() {
        // Cancel subscriptions
        unpairingSubscription?.cancel()
        unpairingSubscription = nil

        // Delete pairing from Convex
        if let pairingId = pairingId {
            Task {
                do {
                    try await ConvexManager.shared.mutationVoid(
                        "pairings:remove",
                        args: ["pairingId": pairingId]
                    )
                    print("✅ Pairing removed from Convex")
                } catch {
                    print("⚠️ Error removing pairing: \(error)")
                }
            }
        }

        DispatchQueue.main.async {
            self.isPaired = false
            self.pairedDeviceName = ""
            self.pairingId = nil
            self.isSetupComplete = false
            self.pairingError = nil
        }

        UserDefaults.standard.removeObject(forKey: "current_pairing_id")
        UserDefaults.standard.removeObject(forKey: "paired_device_name")
        UserDefaults.standard.removeObject(forKey: "is_setup_complete")

        ClipboardManager.shared.clearHistory()
        ClipboardManager.shared.stopMonitoring()
        ClipboardManager.shared.stopListening()
    }

    // Restore previous pairing on app launch (with Boot Time check)
    // If system rebooted > 120s ago vs saved time, invalidates pairing (Security)
    func restorePairing() {
        if let savedPairingId = UserDefaults.standard.string(forKey: "current_pairing_id"),
            let savedDeviceName = UserDefaults.standard.string(forKey: "paired_device_name")
        {

            let currentBootTime = getCurrentBootTime()
            let savedBootTime = UserDefaults.standard.double(forKey: "last_boot_time")

            // Re-validate session freshness
            if abs(currentBootTime - savedBootTime) > 120 {
                unpair()
                return
            }

            self.pairingId = savedPairingId
            self.pairedDeviceName = savedDeviceName
            self.isPaired = true

            self.startMonitoringPairingStatus(pairingId: savedPairingId)
            self.isSetupComplete = UserDefaults.standard.bool(forKey: "is_setup_complete")
        }
    }

    // Mark setup as complete
    func completeSetup() {
        DispatchQueue.main.async {
            self.isSetupComplete = true
        }
        UserDefaults.standard.set(true, forKey: "is_setup_complete")
        UserDefaults.standard.set(getCurrentBootTime(), forKey: "last_boot_time")
    }

    private func getCurrentBootTime() -> TimeInterval {
        return Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    }
}
