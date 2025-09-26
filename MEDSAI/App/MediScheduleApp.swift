import SwiftUI
import FirebaseAuth

@main
struct MediScheduleApp: App {
    // Ensure AppDelegate runs before any Firebase usage
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Make AppSettings available to the whole app
    @StateObject private var settings = AppSettings.shared
    @State private var didAttachAuthListener = false

    // 🔹 NEW: one shared meds repo for all tabs/screens
    @StateObject private var medsRepo = UserMedsRepo()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(medsRepo)          // ✅ inject once so @EnvironmentObject works everywhere

                // Global styling (unchanged)
                .tint(Color(.systemGreen))
                .preferredColorScheme(.light)

                // Optional: configure notifications if you use them
                .onAppear {
                    NotificationsManager.shared.configure()
                    // start Firestore listener once
                    medsRepo.start()
                }

                // Reflect auth state into settings once (unchanged)
                .task {
                    guard !didAttachAuthListener else { return }
                    didAttachAuthListener = true
                    _ = Auth.auth().addStateDidChangeListener { _, user in
                        let signedIn = (user != nil)
                        settings.didChooseEntry = signedIn
                        settings.onboardingCompleted = signedIn
                        if signedIn {
                            settings.loadRoutineFromFirestore()
                        }
                    }
                }
        }
    }
}
