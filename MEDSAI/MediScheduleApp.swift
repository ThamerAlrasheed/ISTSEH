import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth

@main
struct MediScheduleApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var didAttachAuthListener = false

    // Configure Firebase as early as possible
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .modelContainer(for: Medication.self)
                .tint(.green)
                .onAppear {
                    // Safe now because Firebase was configured in init()
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
