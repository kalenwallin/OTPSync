//
// FirebaseManager.swift
// ClipSync - TESTING MODE (No Authentication)
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

class FirebaseManager {
    static let shared = FirebaseManager()
    let db: Firestore
    
    private init() {
        // --- Configuration (Region Aware) ---
        if FirebaseApp.app() == nil {
            let region = UserDefaults.standard.string(forKey: "server_region") ?? "IN"
            print("🌍 Initializing Firebase for Region: \(region)")
            
            if let options = RegionConfig.getOptions(for: region) {
                // Custom Config (US)
                FirebaseApp.configure(options: options)
                print("🇺🇸 Configured with Custom Options (US)")
            } else {
                // Default Config (Info.plist -> India)
                FirebaseApp.configure()
                print("🇮🇳 Configured with Default plist (India)")
            }
        } else {
            print("🔥 Firebase already configured")
        }
        
        db = Firestore.firestore()
        
        // Disable offline persistence to avoid LevelDB lock errors on macOS
        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        
        print("✅ Firebase initialized successfully")
        print("📦 Offline persistence: DISABLED (MacOS Fix)")
        
        // Test network connectivity
        testNetworkConnection()
        
        // TESTING MODE: Skip authentication
        print("⚠️ TESTING MODE: Running without Firebase Authentication")
        print("⚠️ Make sure Firestore rules allow unauthenticated access!")
    }
    
    // --- Connectivity Test ---
    // Test if app has network access (Sandbox check)
    private func testNetworkConnection() {
        guard let url = URL(string: "https://www.google.com") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ NETWORK TEST FAILED: \(error.localizedDescription)")
                print("💡 App might not have network entitlements!")
            } else {
                print("✅ Network access confirmed")
            }
        }
        task.resume()
    }
    
    // --- Testing Helpers ---
    // TESTING MODE: Skip auth completely
    func waitForAuth(timeout: TimeInterval = 15.0, completion: @escaping (Bool) -> Void) {
        print("⚠️ TESTING MODE: Skipping authentication")
        completion(true)
    }
    
    // Helper: Check if Firebase is ready
    var isReady: Bool {
        return FirebaseApp.app() != nil
    }
    
    // Helper: Get collection reference
    func collection(_ path: String) -> CollectionReference {
        return db.collection(path)
    }
}
