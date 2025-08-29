import SwiftUI

struct RootTabView: View {
    @State private var selection: Int = 1 // 0 Today, 1 Schedule, 2 Meds, 3 Settings

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem {
                    Image(systemName: "calendar.badge.clock")
                    Text("Today")
                }
                .tag(0)

            SchedulePageView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Schedule")
                }
                .tag(1)

            MedListView()
                .tabItem {
                    Image(systemName: "pills.fill")
                    Text("Meds")
                }
                .tag(2)

            SettingsView() // <- UI view, NOT the AppSettings class
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(3)
        }
    }
}
