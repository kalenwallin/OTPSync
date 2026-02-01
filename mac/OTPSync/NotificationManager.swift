//
// NotificationManager.swift
// OTPSync
//

import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    /// Sends a notification when clipboard content is synced from Android
    func sendClipboardSyncNotification(content: String, deviceName: String) {
        // Check if user has notifications enabled
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let notificationContent = UNMutableNotificationContent()
            notificationContent.title = "Clipboard Synced"

            // Truncate content for preview (max 50 chars)
            let preview =
                content.count > 50
                ? String(content.prefix(47)) + "..."
                : content

            notificationContent.body = "From \(deviceName): \(preview)"
            notificationContent.sound = .default

            // Use a unique identifier for each notification
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: notificationContent,
                trigger: nil  // Deliver immediately
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to send notification: \(error)")
                }
            }
        }
    }
}
