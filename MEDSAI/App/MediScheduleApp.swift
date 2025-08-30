import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth
import UserNotifications

@main
struct MediScheduleApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var didAttachAuthListener = false

    // Configure Firebase + notifications early
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // Notifications categories + delegate
        NotificationsManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .modelContainer(for: Medication.self)
                .tint(.green)
                .onAppear {
                    // ask notification permission once at first entry (safe to call again later)
                    Task { _ = await NotificationsManager.shared.requestAuthorization() }

                    guard !didAttachAuthListener else { return }
                    didAttachAuthListener = true
                    Auth.auth().addStateDidChangeListener { _, user in
                        if user != nil {
                            settings.didChooseEntry = true
                            settings.onboardingCompleted = true
                        } else {
                            settings.didChooseEntry = false
                            settings.onboardingCompleted = false
                        }
                    }
                }
        }
    }
}
