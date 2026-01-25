//
// FirebaseManager.swift
// ClipSync - No Auth (E2E Encrypted)
//

import Foundation
import FirebaseCore
import FirebaseFirestore

class FirebaseManager {
    static let shared = FirebaseManager()
    let db: Firestore
    
    private init() {
        // --- Configuration (Region Aware) ---
        if FirebaseApp.app() == nil {
            let region = UserDefaults.standard.string(forKey: "server_region") ?? "IN"
            print(" Initializing Firebase for Region: \(region)")
            
            if let options = RegionConfig.getOptions(for: region) {
                // Custom Config (US)
                FirebaseApp.configure(options: options)
                print(" Configured with Custom Options (US)")
            } else {
                // Default Config (Info.plist -> India)
                FirebaseApp.configure()
                print(" Configured with Default plist (India)")
            }
        } else {
            print(" Firebase already configured")
        }
        
        db = Firestore.firestore()
        
        // Disable offline persistence to avoid LevelDB lock errors on macOS
        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        
        print(" Firebase initialized successfully")
        print(" Security: E2E Encryption (No Auth Required)")
        print(" Offline persistence: DISABLED (MacOS Fix)")
        
        // Test network connectivity
        testNetworkConnection()
    }
    
    // --- Connectivity Test ---
    private func testNetworkConnection() {
        guard let url = URL(string: "https://www.google.com") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print(" NETWORK TEST FAILED: \(error.localizedDescription)")
                print(" App might not have network entitlements!")
            } else {
                print(" Network access confirmed")
            }
        }
        task.resume()
    }
    
    // Helper: Check if Firebase is ready
    var isReady: Bool {
        return FirebaseApp.app() != nil
    }
    
    var isAuthenticated: Bool {
        return true  // Always true since we don't use auth
    }
    
    // Helper: Get collection reference
    func collection(_ path: String) -> CollectionReference {
        return db.collection(path)
    }
}
