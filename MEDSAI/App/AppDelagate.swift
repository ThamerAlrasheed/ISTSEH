// AppDelegate.swift
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Supabase initializes lazily via SupabaseManager.shared — no explicit configure needed.

        // Notifications: delegate + categories
        NotificationsManager.shared.configure()

        // (Optional) Ask for permission right away; you also request later in Today view.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        return true
    }
}
