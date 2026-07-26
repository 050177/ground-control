import AppKit
import Foundation
import UserNotifications

/// macOS notifications for HOLDING / LANDED, with a dock-bounce fallback
/// (handy when notification permission hasn't been granted).
enum Notify {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if !granted {
                    print("[notify] permission not granted — falling back to dock bounce")
                }
            }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                bounceDock()
            }
        }
    }

    static func bounceDock() {
        DispatchQueue.main.async {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }
}
