//
// PairingManager.swift
// ClipSync
//

import Foundation
import FirebaseFirestore
import Combine

class PairingManager: ObservableObject {
    static let shared = PairingManager()
    
    @Published var isPaired: Bool = UserDefaults.standard.string(forKey: "current_pairing_id") != nil
    @Published var pairedDeviceName: String = UserDefaults.standard.string(forKey: "paired_device_name") ?? ""
    @Published var pairingId: String? = UserDefaults.standard.string(forKey: "current_pairing_id")
    @Published var isSetupComplete: Bool = UserDefaults.standard.bool(forKey: "is_setup_complete")
    @Published var pairingError: String? = nil // NEW: For displaying errors to user
    
    private var pairingListener: ListenerRegistration?
    private var unpairingListener: ListenerRegistration?
    private let db = FirebaseManager.shared.db
    private var listenStartTime: Date?
    
    // --- Pairing Handshake ---
    // Listens for a new document in 'pairings' collection with matching macId
    func listenForPairing(macDeviceId: String) {
        guard !isPaired else { return }
        
        // Time window: Only accept pairings created AFTER now
        listenStartTime = Date().addingTimeInterval(-60)
        
        DispatchQueue.main.async { self.pairingError = nil }
        
        // Ensure Auth before listening
        FirebaseManager.shared.waitForAuth(timeout: 20.0) { [weak self] success in
            guard let self = self else { return }
            if !success {
                DispatchQueue.main.async {
                    self.pairingError = "Connection failed. Check internet and restart app."
                }
                return
            }
            self.startFirestoreListener(macDeviceId: macDeviceId)
        }
    }
    
    private func startFirestoreListener(macDeviceId: String) {

        
        // Query pairings collection where macId matches
        pairingListener = db.collection("pairings")
            .whereField("macId", isEqualTo: macDeviceId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    if nsError.code == 7 {
                        DispatchQueue.main.async {
                            self.pairingError = "Permission denied. Check Firestore rules."
                        }
                    } else if nsError.code == 14 {
                        DispatchQueue.main.async {
                            self.pairingError = "Network error. Check connection."
                        }
                    }
                    return
                }
                
                if documents.isEmpty {
                    return
                }
                
                // Process snapshots

                
                // Find the most recent VALID pairing
                self.processDocuments(documents)
            }
    }
    
    private func processDocuments(_ documents: [QueryDocumentSnapshot]) {
        var validPairing: QueryDocumentSnapshot?
        
        for doc in documents {
            let data = doc.data()
            
            // Check if pairing has timestamp
            guard let timestamp = data["timestamp"] as? Timestamp else {
                continue
            }
            
            let pairingDate = timestamp.dateValue()
            
            // Only accept pairings created AFTER we started listening
            if let startTime = self.listenStartTime {
                if pairingDate > startTime {
                    validPairing = doc
                    break
                }
            }
        
        guard let pairingDoc = validPairing else {
            return
        }
        
        // Process the valid pairing
        self.processPairingData(pairingDoc)
    }
    
    private func processPairingData(_ doc: QueryDocumentSnapshot) {
        let data = doc.data()
        guard let androidDeviceName = data["androidDeviceName"] as? String else { return }
        let pairingId = doc.documentID

        // Save State (Memory)
        DispatchQueue.main.async {
            self.pairingId = pairingId
            self.pairedDeviceName = androidDeviceName
            self.isPaired = true
            self.pairingError = nil
        }
        
        // Persistence (Disk)
        UserDefaults.standard.set(pairingId, forKey: "current_pairing_id")
        UserDefaults.standard.set(androidDeviceName, forKey: "paired_device_name")
        
        // Start Unpair Watcher
        self.startMonitoringPairingStatus(pairingId: pairingId)
        
        // Cleanup Listener
        self.pairingListener?.remove()
        self.pairingListener = nil
    }
    
    // --- Persistence & Restoration ---
    
    // Monitors for remote unpair (deletion of document)
    func startMonitoringPairingStatus(pairingId: String) {
        unpairingListener?.remove()

        unpairingListener = db.collection("pairings").document(pairingId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if error != nil { return }
                
                // If document is gone, we are unpaired
                if let snapshot = snapshot, !snapshot.exists {
                    self.unpair()
                }
            }
    }
    
    // Stop listening
    func stopListening() {
        pairingListener?.remove()
        pairingListener = nil
        listenStartTime = nil
        pairingListener?.remove()
        pairingListener = nil
        listenStartTime = nil
    }
    
    // Unpair device
    func unpair() {
        unpairingListener?.remove()
        unpairingListener = nil
        
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
        
        ClipboardManager.shared.stopListening()
    }
    
    // Restore previous pairing on app launch (with Boot Time check)
    // If system rebooted > 120s ago vs saved time, invalidates pairing (Security)
    func restorePairing() {
        if let savedPairingId = UserDefaults.standard.string(forKey: "current_pairing_id"),
           let savedDeviceName = UserDefaults.standard.string(forKey: "paired_device_name") {
            
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
        
        UserDefaults.standard.set(true, forKey: "is_setup_complete")
        UserDefaults.standard.set(getCurrentBootTime(), forKey: "last_boot_time")
    }
    
    private func getCurrentBootTime() -> TimeInterval {
        return Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    }
}
