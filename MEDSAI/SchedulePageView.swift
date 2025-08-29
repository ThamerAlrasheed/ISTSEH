import SwiftUI

/// Calendar page:
/// - Top: monthly/weekly calendar (tap a day to select)
/// - Bottom: two read-only sections for the selected date:
///     1) Doses (advanced Scheduler from Helpers.swift)
///     2) Appointments (user-created, read-only here)
///
/// If there are no doses, we show just "No doses" and nothing else.
/// If there are no appointments, we show an "Add appointment" button to create one.
struct SchedulePageView: View {
    @EnvironmentObject var settings: AppSettings

    // Medications (same repo you already use for Today)
    @StateObject private var repo = UserMedsRepo()

    // Appointments (new Firestore repo)
    @StateObject private var appts = AppointmentsRepo()

    // Selected calendar day (defaults to today)
    @State private var selectedDate: Date = Date()

    // Read-only list of (time, LocalMed) pairs for the selected day
    @State private var dayDoses: [(Date, LocalMed)] = []

    // Sheet to add appointments
    @State private var showAddAppointment = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Calendar (weekly/monthly toggle) — user taps a day to select
                CalendarView(selection: $selectedDate, initialMode: .monthly)
                    .padding(.bottom, 8)
                    .background(Color(.systemBackground))

                Divider()

                // The content for the selected day
                List {
                    dosesSection

                    appointmentsSection
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Calendar")
            .onAppear {
                repo.start()
                appts.start()      // Begin listening to Firestore appointments for this user
                recomputeDoses()
            }
            .onChange(of: selectedDate) { _, _ in
                recomputeDoses()
            }
            .onChange(of: repo.meds) { _, _ in
                recomputeDoses()
            }
            .onChange(of: settings.breakfast) { _, _ in recomputeDoses() }
            .onChange(of: settings.lunch)     { _, _ in recomputeDoses() }
            .onChange(of: settings.dinner)    { _, _ in recomputeDoses() }
            .onChange(of: settings.bedtime)   { _, _ in recomputeDoses() }
            .onChange(of: settings.wakeup)    { _, _ in recomputeDoses() }
            .sheet(isPresented: $showAddAppointment) {
                AddAppointmentView(repo: appts, defaultDate: selectedDate)
            }
        }
    }

    // MARK: - Sections

    // 1) DOSES
    @ViewBuilder
    private var dosesSection: some View {
        Section {
            if repo.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading medications…")
                }
            } else if let err = repo.errorMessage {
                ContentUnavailableView("Couldn't load medications",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(err))
            } else if dayDoses.isEmpty {
                // Per your requirement: if no doses, display only "No doses" and nothing else.
                ContentUnavailableView("No doses on this day",
                                       systemImage: "calendar.badge.exclamationmark")
            } else {
                ForEach(dayDoses.indices, id: \.self) { i in
                    let (time, med) = dayDoses[i]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name)
                                .font(.headline)
                            Text("\(med.dosage) • \(foodRuleLabel(med.foodRule))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    // Read-only: no swipe actions, no checkmarks
                }
            }
        } header: {
            Text(sectionTitle("Doses"))
        }
    }

    // 2) APPOINTMENTS
    @ViewBuilder
    private var appointmentsSection: some View {
        // If no doses, you said "display no doses without anything else".
        // That means we hide appointments entirely when no doses.
        if !dayDoses.isEmpty {
            Section {
                let items = appts.appointments(on: selectedDate)
                if appts.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading appointments…")
                    }
                } else if let err = appts.errorMessage {
                    ContentUnavailableView("Couldn't load appointments",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                } else if items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No appointments on this day.")
                            .foregroundStyle(.secondary)
                        Button {
                            showAddAppointment = true
                        } label: {
                            Label("Add appointment", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(items) { appt in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appt.title)
                                    .font(.headline)
                                if let loc = appt.location, !loc.isEmpty {
                                    Text(loc).foregroundStyle(.secondary)
                                }
                                if let notes = appt.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(timeOnly(appt.date))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        showAddAppointment = true
                    } label: {
                        Label("Add appointment", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text(sectionTitle("Appointments"))
            }
        }
    }

    // MARK: - Build Doses for selected day (READ-ONLY)

    private func recomputeDoses() {
        guard repo.isSignedIn else {
            dayDoses = []
            return
        }

        // Only meds active on the selected day
        let active = repo.meds.filter { med in
            guard !med.isArchived else { return false }
            return (med.startDate ... med.endDate).contains(selectedDate)
        }
        if active.isEmpty {
            dayDoses = []
            return
        }

        // Adapt LocalMed -> Medication (keep SAME IDs for mapping back)
        let adapted: [Medication] = active.map { m in
            Medication(
                id: m.id,
                name: m.name,
                dosage: m.dosage,
                frequencyPerDay: m.frequencyPerDay,
                startDate: m.startDate,
                endDate: m.endDate,
                foodRule: m.foodRule,
                notes: m.notes,
                ingredients: m.ingredients,
                minIntervalHours: m.minIntervalHours
            )
        }

        // Use the advanced scheduler for that specific day
        let pairs = Scheduler.buildAdherenceSchedule(
            meds: adapted,
            settings: settings,
            date: selectedDate
        )

        // Map Medication.id -> LocalMed to return (time, LocalMed)
        let byId: [String: LocalMed] = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let display: [(Date, LocalMed)] = pairs.compactMap { (t, med) in
            guard let local = byId[med.id] else { return nil }
            return (t, local)
        }
        dayDoses = display.sorted { $0.0 < $1.0 }
    }

    // MARK: - Formatting helpers

    private func sectionTitle(_ base: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return "\(base) – \(df.string(from: selectedDate))"
    }

    private func foodRuleLabel(_ rule: FoodRule) -> String {
        switch rule {
        case .beforeFood: return "Before food"
        case .afterFood:  return "After food"
        case .none:       return "No food rule"
        }
    }

    private func timeOnly(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
