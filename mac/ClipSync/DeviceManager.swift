//
// DeviceManager.swift
// ClipSync
//

import Foundation
import IOKit

class DeviceManager {
    static let shared = DeviceManager()
    
    private let deviceIdKey = "mac_device_id"
    
    // Get or create unique Mac device ID (Randomly generated, not hardware serial)
    func getDeviceId() -> String {
        // Check if already exists in UserDefaults
        if let existingId = UserDefaults.standard.string(forKey: deviceIdKey) {
        if let existingId = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existingId
        }
        
        // Generate new random UUID
        let deviceId = UUID().uuidString
        UserDefaults.standard.set(deviceId, forKey: deviceIdKey)
        let deviceId = UUID().uuidString
        UserDefaults.standard.set(deviceId, forKey: deviceIdKey)
        return deviceId
    }
    
    // Get Mac computer name (for display in Android)
    func getMacName() -> String {
        return Host.current().localizedName ?? "Mac"
    }
    
    // Get friendly name for UI (e.g. "Bhanu's Mac")
    func getFriendlyMacName() -> String {
        let fullName = getMacName()
        let components = fullName.split(separator: " ")
        if let firstWord = components.first {
            let name = String(firstWord)
            // Handle existing possessive
            if name.hasSuffix("'s") || name.hasSuffix("’s") {
                return "\(name) Mac"
            }
            return "\(name)'s Mac"
        }
        return "My Mac"
    }
}

