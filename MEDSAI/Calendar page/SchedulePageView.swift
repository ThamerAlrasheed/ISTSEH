import SwiftUI

/// Calendar page – calendar picker at the top, then Appointments, then Doses.
struct SchedulePageView: View {
    @EnvironmentObject var settings: AppSettings

    @StateObject private var repo = UserMedsRepo()
    @StateObject private var appts = AppointmentsRepo()

    @State private var selectedDate: Date = Date()
    @State private var dayDoses: [(Date, LocalMed)] = []

    @State private var showAddAppointment = false
    @State private var editingAppointment: Appointment? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Calendar picker — inline at top
                    CalendarView(selection: $selectedDate, initialMode: .monthly)
                        .padding(.bottom, 4)

                    Divider().padding(.horizontal)

                    // Appointments
                    appointmentsBlock

                    // Doses
                    dosesBlock
                }
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Calendar")
            .onAppear {
                repo.start()
                appts.start()
                recomputeDoses()
            }
            .onChange(of: selectedDate) { _, _ in recomputeDoses() }
            .onChange(of: repo.meds) { _, _ in recomputeDoses() }
            .onChange(of: settings.breakfast) { _, _ in recomputeDoses() }
            .onChange(of: settings.lunch)     { _, _ in recomputeDoses() }
            .onChange(of: settings.dinner)    { _, _ in recomputeDoses() }
            .onChange(of: settings.bedtime)   { _, _ in recomputeDoses() }
            .onChange(of: settings.wakeup)    { _, _ in recomputeDoses() }
            .sheet(isPresented: $showAddAppointment) {
                AddAppointmentView(repo: appts, defaultDate: selectedDate, existing: nil)
            }
            .sheet(item: $editingAppointment) { appt in
                AddAppointmentView(repo: appts, defaultDate: selectedDate, existing: appt)
            }
        }
    }

    // MARK: - Appointments block (above doses)
    private var appointmentsBlock: some View {
        SectionCard {
            SectionHeader(title: sectionTitle("Appointments"))

            let items = appts.appointments(on: selectedDate)

            if appts.isLoading {
                rowPadding(
                    HStack { ProgressView(); Text("Loading appointments…") }
                )
            } else if let err = appts.errorMessage {
                rowPadding(
                    ContentUnavailableView("Couldn't load appointments",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                )
            } else if items.isEmpty {
                VStack(alignment: .center, spacing: 10) {
                    Text("No appointments on this day.")
                        .foregroundStyle(.secondary)

                    // Centered, perfectly centered text inside the green pill
                    HStack {
                        Spacer()
                        CenteredPillButton(title: "Add appointment") {
                            showAddAppointment = true
                        }
                        .frame(maxWidth: 260)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { appt in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appt.titleWithEmoji).font(.headline)
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

                                Menu {
                                    Button { editingAppointment = appt } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        Task { await appts.delete(appt) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)
                    }

                    // Centered "Add appointment" pill under list
                    HStack {
                        Spacer()
                        CenteredPillButton(title: "Add appointment") {
                            showAddAppointment = true
                        }
                        .frame(maxWidth: 260)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Doses block (read-only, with empty state)
    private var dosesBlock: some View {
        SectionCard {
            SectionHeader(title: sectionTitle("Doses"))

            if repo.isLoading {
                rowPadding(
                    HStack { ProgressView(); Text("Loading medications…") }
                )
            } else if let err = repo.errorMessage {
                rowPadding(
                    ContentUnavailableView("Couldn't load medications",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                )
            } else if dayDoses.isEmpty {
                rowPadding(
                    ContentUnavailableView("No doses on this day",
                                           systemImage: "calendar.badge.exclamationmark")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(dayDoses.indices, id: \.self) { i in
                        let pair = dayDoses[i]
                        let time = pair.0
                        let med  = pair.1

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.name).font(.headline)
                                Text("\(med.dosage) • \(foodRuleLabel(med.foodRule))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(time.formatted(date: .omitted, time: .shortened))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Build Doses for selected day (READ-ONLY)
    private func recomputeDoses() {
        guard repo.isSignedIn else {
            dayDoses = []
            return
        }

        let active = repo.meds.filter { med in
            guard !med.isArchived else { return false }
            return (med.startDate ... med.endDate).contains(selectedDate)
        }
        if active.isEmpty {
            dayDoses = []
            return
        }

        // Adapt LocalMed -> Medication (keep SAME IDs)
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

        let pairs = Scheduler.buildAdherenceSchedule(
            meds: adapted,
            settings: settings,
            date: selectedDate
        )

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

    private func rowPadding<V: View>(_ v: V) -> some View {
        v.padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Section chrome (List-like look without List)
private struct SectionCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}

// MARK: - Button
private struct CenteredPillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(minWidth: 160, maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .contentShape(Rectangle())
        }
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
