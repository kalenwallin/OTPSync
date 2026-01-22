// 
// ClipboardItem.swift
// ClipSync
//

import Foundation

enum ClipboardDirection {
    case sent
    case received
}

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let timestamp: Date
    let deviceName: String
    let direction: ClipboardDirection
    
    // Helper for "2s ago"
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
