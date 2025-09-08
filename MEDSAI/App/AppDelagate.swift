// AppDelegate.swift
import UIKit
import FirebaseCore
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Firebase (your project already uses it)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // Notifications: delegate + categories
        NotificationsManager.shared.configure()

        // (Optional) Ask for permission right away; you also request later in Today view.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        return true
    }
}
