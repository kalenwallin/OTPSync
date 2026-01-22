//
//  RegionConfig.swift
//  ClipSync
//
//  Created for Multi-Region Support
//

import Foundation
import FirebaseCore

struct RegionConfig {
    static let REGION_INDIA = "IN"
    static let REGION_US = "US"
    
    // US Project Credentials
    // Derived from your GoogleService-Info.plist
    struct US {
        static let projectID = "clipsync1-c3c3c"
        static let googleAppID = "1:421995011629:ios:b635a91ef5b7399f8a22a4" // From iOS/Mac plist
        static let gcmSenderID = "421995011629"
        static let storageBucket = "clipsync1-c3c3c.firebasestorage.app"
        static let apiKey = "AIzaSyBlG45LxPYuG6ZY-jgcAFe0gvoJF7WfsnY" // Transcribed from Screenshot
    }
    
    static func getOptions(for region: String) -> FirebaseOptions? {
        if region == REGION_US {
            let options = FirebaseOptions(googleAppID: US.googleAppID, gcmSenderID: US.gcmSenderID)
            options.apiKey = US.apiKey
            options.projectID = US.projectID
            options.storageBucket = US.storageBucket
            return options
        }
        
        // India uses the default bundled plist
        return nil
    }
}
