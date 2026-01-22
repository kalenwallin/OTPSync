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
    
    // Listen for Android to scan QR and create pairing
    func listenForPairing(macDeviceId: String) {
        guard !isPaired else {
            return
        }
        
        // Record when we started listening (with buffer for clock skew)
        listenStartTime = Date().addingTimeInterval(-60)
        
        // Clear any previous errors
        DispatchQueue.main.async {
            self.pairingError = nil
        }
        
        // Wait for Auth to complete before listening - WITH ERROR HANDLING
        FirebaseManager.shared.waitForAuth(timeout: 20.0) { [weak self] success in
            guard let self = self else { return }
            
            if !success {
                // Handle auth failure
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
        
        // Validate required fields
        guard let androidDeviceName = data["androidDeviceName"] as? String else {
        }

        
        // Save pairing info
        DispatchQueue.main.async {
            self.pairingId = pairingId
            self.pairedDeviceName = androidDeviceName
            self.isPaired = true
            self.pairingError = nil
        }
        
        // Store locally for persistence
        UserDefaults.standard.set(pairingId, forKey: "current_pairing_id")
        UserDefaults.standard.set(androidDeviceName, forKey: "paired_device_name")
        UserDefaults.standard.set(pairingId, forKey: "current_pairing_id")
        UserDefaults.standard.set(androidDeviceName, forKey: "paired_device_name")
        
        // Start monitoring for unpairing
        self.startMonitoringPairingStatus(pairingId: pairingId)
        
        // Stop listening after successful pairing
        self.pairingListener?.remove()
        self.pairingListener = nil
        self.pairingListener = nil
    }
    
    // Start constantly monitoring the pairing document
    func startMonitoringPairingStatus(pairingId: String) {
        unpairingListener?.remove()
        
        unpairingListener?.remove()

        
        unpairingListener = db.collection("pairings").document(pairingId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                if let error = error {
                    // Monitor error
                    return
                }
                
                if let snapshot = snapshot, !snapshot.exists {
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
    
    // Restore previous pairing on app launch
    func restorePairing() {
        if let savedPairingId = UserDefaults.standard.string(forKey: "current_pairing_id"),
           let savedDeviceName = UserDefaults.standard.string(forKey: "paired_device_name") {
            
            let currentBootTime = getCurrentBootTime()
            let savedBootTime = UserDefaults.standard.double(forKey: "last_boot_time")
            
            if abs(currentBootTime - savedBootTime) > 120 {
            if abs(currentBootTime - savedBootTime) > 120 {
                unpair()
                return
            }
            
            self.pairingId = savedPairingId
            self.pairedDeviceName = savedDeviceName
            self.isPaired = true
            
            self.startMonitoringPairingStatus(pairingId: savedPairingId)
            self.isSetupComplete = UserDefaults.standard.bool(forKey: "is_setup_complete")
            
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
