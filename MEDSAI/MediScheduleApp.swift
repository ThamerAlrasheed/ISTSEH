import SwiftUI
import SwiftData

@main
struct MedAiApp: App {
    @StateObject private var settings = AppSettings.shared
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
        }
        .modelContainer(for: [Medication.self, Dose.self])
    }
}
