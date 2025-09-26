import SwiftUI

struct RootTabView: View {
    // Read shared objects injected in MediScheduleApp (do not inject here)
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var medsRepo: UserMedsRepo

    @State private var selection: Int = 1 // 0 Today, 1 Schedule, 2 Meds, 3 Settings

    var body: some View {
        ZStack(alignment: .bottom) {

            // Real TabView for navigation/state — stock bar is fully hidden
            TabView(selection: $selection) {
                TodayScheduleView().tag(0)
                SchedulePageView().tag(1)
                MedListView().tag(2)
                SettingsView().tag(3)
            }
            .toolbar(.hidden, for: .tabBar) // hide Apple's tab bar (iOS 16+)
            .onAppear {
                UITabBar.appearance().isHidden = true // extra safety
            }

            // Custom glass bar (the only bar you see)
            GlassTabBar(selection: $selection)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .ignoresSafeArea(.keyboard) // don’t jump when keyboard appears
        }
    }
}

// MARK: - Glass Tab Bar

private struct GlassTabBar: View {
    @Binding var selection: Int

    private struct Item: Identifiable {
        let id: Int
        let title: String
        let systemImage: String
    }

    // Order must match the TabView tags above
    private let items: [Item] = [
        .init(id: 0, title: "Today",    systemImage: "calendar.badge.clock"),
        .init(id: 1, title: "Schedule", systemImage: "calendar"),
        .init(id: 2, title: "Meds",     systemImage: "pills.fill"),
        .init(id: 3, title: "Settings", systemImage: "gearshape")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                GlassTabButton(
                    isSelected: selection == item.id,
                    title: item.title,
                    systemImage: item.systemImage
                ) {
                    selection = item.id
                }
                .frame(maxWidth: .infinity) // equal width per tab
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10) // a bit taller to fit icon+label
        .background(.ultraThinMaterial) // iOS glass/frosted effect
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 2,  x: 0, y: 1)
    }
}

private struct GlassTabButton: View {
    let isSelected: Bool
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) { // 👈 icon on top, text underneath
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85) // prefer slight shrink over ellipses
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isSelected ? 0.35 : 0.18),
                                lineWidth: isSelected ? 0.8 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
