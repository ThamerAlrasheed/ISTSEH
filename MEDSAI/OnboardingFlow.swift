import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject var settings: AppSettings
    @State private var step = 1
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if step == 1 {
                    Text("Set your daily routine")
                        .font(.title).bold()
                    RoutinePickers()
                    Button("Continue") { step = 2 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("Notifications")
                        .font(.title).bold()
                    Text("I’ll remind you gently when it’s time for your meds.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Allow reminders") {
                        Task { await Notifier.requestAuth(); settings.onboardingCompleted = true }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Skip for now") { settings.onboardingCompleted = true }
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct RoutinePickers: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimeRow(title: "Breakfast", comps: $settings.breakfast)
            TimeRow(title: "Lunch", comps: $settings.lunch)
            TimeRow(title: "Dinner", comps: $settings.dinner)
            Divider().padding(.vertical, 8)
            TimeRow(title: "Bedtime", comps: $settings.bedtime)
            TimeRow(title: "Wake up", comps: $settings.wakeup)
        }
    }
}

struct TimeRow: View {
    let title: String
    @Binding var comps: DateComponents
    
    var body: some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            DatePicker("", selection: Binding(
                get: { Calendar.current.date(from: comps) ?? Date() },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour,.minute], from: date)
                    comps.hour = parts.hour; comps.minute = parts.minute
                }), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
        .font(.title3)
    }
}
