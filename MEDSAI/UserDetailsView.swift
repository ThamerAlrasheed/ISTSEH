import SwiftUI

/// Screen to view & edit the user's routine:
/// - Meal schedule: Breakfast / Lunch / Dinner
/// - Sleep schedule: Bedtime / Wake up
///
/// Values are bound directly to AppSettings.DateComponents and save immediately.
struct UserDetailsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Meal Schedule") {
                SettingTimeRow(title: "Breakfast", comps: $settings.breakfast, defaultHour: 8,  defaultMinute: 0)
                SettingTimeRow(title: "Lunch",     comps: $settings.lunch,     defaultHour: 13, defaultMinute: 0)
                SettingTimeRow(title: "Dinner",    comps: $settings.dinner,    defaultHour: 19, defaultMinute: 0)
            }

            Section("Sleep Schedule") {
                SettingTimeRow(title: "Bedtime",   comps: $settings.bedtime,   defaultHour: 23, defaultMinute: 0)
                SettingTimeRow(title: "Wake up",   comps: $settings.wakeup,    defaultHour: 7,  defaultMinute: 0)
            }

            Section(footer:
                Text("Changes are saved automatically and used for your daily medication schedule.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            ) {
                EmptyView()
            }
        }
        .navigationTitle("User Details")
    }
}

// MARK: - Reusable row binding DateComponents <-> Date
/// Named uniquely to avoid clashing with other `TimeRow/RoutineRow` types in your project.
private struct SettingTimeRow: View {
    let title: String
    @Binding var comps: DateComponents
    let defaultHour: Int
    let defaultMinute: Int

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            DatePicker(
                "",
                selection: Binding<Date>(
                    get: { Calendar.current.date(from: comps) ?? defaultDate() },
                    set: { newDate in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        comps.hour = parts.hour
                        comps.minute = parts.minute
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .font(.title3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func defaultDate() -> Date {
        Calendar.current.date(from: DateComponents(hour: defaultHour, minute: defaultMinute)) ?? Date()
    }
}
