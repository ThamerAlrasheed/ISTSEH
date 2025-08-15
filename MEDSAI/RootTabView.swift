import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            // Today tab (rename TodayView() if your type is different)
            TodayView()
                .tabItem {
                    Image(systemName: "calendar.badge.clock")
                    Text("Today")
                }
            
            ScheduleView()              // ← your weekly schedule screen
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Schedule")
                }
            
            // Meds tab
            MedListView()
                .tabItem {
                    Image(systemName: "pills.fill")
                    Text("Meds")
                }

            // Settings tab (placeholder so it compiles)
            AppSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
        }
    }
}

// Simple placeholder so the project builds
struct AppSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        NavigationStack {
            Form {
                Section("App") {
                    Toggle("Onboarding completed", isOn: $settings.onboardingCompleted)
                }
                Section("Debug") {
                    Button("Reset entry (show Landing again)") {
                        settings.didChooseEntry = false
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
