// ScheduleView.swift
import SwiftUI

/// Apple Calendar–style screen with Weekly/Monthly toggle.
/// Uses the reusable `CalendarView` component.
struct ScheduleView: View {
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // The reusable calendar you already have
                CalendarView(
                    selection: $selectedDate,
                    initialMode: .weekly,              // or .monthly to default to month
                    calendar: .current,
                    allowsSelectingOutsideCurrentMonth: true
                )

                Divider().padding(.horizontal)

                // For now, just show which date is selected.
                // (You can swap this with your day agenda later.)
                VStack(spacing: 8) {
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.headline)
                    Text("Tap any day to select it. Weekly/Monthly switch is above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 8)
            .navigationTitle("Schedule")
        }
    }
}
