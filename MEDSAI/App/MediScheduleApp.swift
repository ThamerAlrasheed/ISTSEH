import SwiftUI

@main
@MainActor
struct MediScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var settings = AppSettings.shared
    @StateObject private var medsRepo = UserMedsRepo()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(medsRepo)
                .tint(Color(.systemGreen))
                .preferredColorScheme(settings.colorScheme)
                .onAppear {
                    NotificationsManager.shared.configure()
                    medsRepo.start()
                }
                .task {
                    await restoreSession()
                }
        }
    }

    /// Restore the user's session on launch.
    /// Checks the backend JWT session first, then falls back to a device-token patient session.
    private func restoreSession() async {
        guard SessionStore.shared.hasSession else {
            settings.didChooseEntry = false
            settings.onboardingCompleted = false
            return
        }

        do {
            if let user = try await AuthRepository.shared.restoreSession() {
                settings.role = UserRole(rawValue: user.role) ?? .regular
                settings.didChooseEntry = true
                settings.onboardingCompleted = true
                await settings.loadRoutineFromBackend()
                return
            }
        } catch {
            print("⚠️ restoreSession failed:", error.localizedDescription)
        }

        SessionStore.shared.clear()
        settings.role = .regular
        settings.didChooseEntry = false
        settings.onboardingCompleted = false
    }
}
