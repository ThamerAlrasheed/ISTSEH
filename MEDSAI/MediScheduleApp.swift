import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth

@main
struct MediScheduleApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var didAttachAuthListener = false

    init() {
        FirebaseApp.configure()
        // ❌ Do NOT add the auth listener here (causes 'mutating self' error)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .modelContainer(for: Medication.self)
                .tint(.green)
                // ✅ Attach the auth listener from the view layer, once.
                .onAppear {
                    guard !didAttachAuthListener else { return }
                    didAttachAuthListener = true

                    Auth.auth().addStateDidChangeListener { _, user in
                        // Drive your app flow from Firebase auth state
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
