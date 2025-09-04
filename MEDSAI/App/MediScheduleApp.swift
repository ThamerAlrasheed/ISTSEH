import SwiftUI
import FirebaseAuth

@main
struct MediScheduleApp: App {
    // Ensure AppDelegate runs before any Firebase usage
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Make AppSettings available to the whole app
    @StateObject private var settings = AppSettings.shared
    @State private var didAttachAuthListener = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                // ✅ Global styling
                .tint(Color(.systemGreen))          // buttons, links, pickers, tab selection, etc.
                .preferredColorScheme(.light)       // white backgrounds, dark text (like before)
                .task {
                    // Reflect auth state into settings once
                    guard !didAttachAuthListener else { return }
                    didAttachAuthListener = true
                    _ = Auth.auth().addStateDidChangeListener { _, user in
                        let signedIn = (user != nil)
                        settings.didChooseEntry = signedIn
                        settings.onboardingCompleted = signedIn
                    }
                }
        }
    }
}
