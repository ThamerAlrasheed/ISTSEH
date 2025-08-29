import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth

@main
struct MediScheduleApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var didAttachAuthListener = false

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
                    guard !didAttachAuthListener else { return }
                    didAttachAuthListener = true

                    Auth.auth().addStateDidChangeListener { _, user in
                        if user != nil {
                            settings.didChooseEntry = true
                            settings.onboardingCompleted = true
                            // Pull latest routine from Firestore so UI + scheduler match the console
                            settings.loadRoutineFromFirestore()
                        } else {
                            settings.didChooseEntry = false
                            settings.onboardingCompleted = false
                        }
                    }
                }
        }
    }
}
