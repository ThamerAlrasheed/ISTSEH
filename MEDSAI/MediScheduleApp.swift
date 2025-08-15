import SwiftUI
import SwiftData

@main
struct MediScheduleApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .modelContainer(for: Medication.self)
                // Global UI tint for system controls (iOS 15+)
                .tint(.green)
        }
    }
}
