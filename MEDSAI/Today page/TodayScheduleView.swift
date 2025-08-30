import SwiftUI
import UserNotifications

/// "Today" page:
/// - Shows today's Appointments (tap to see details) with a checkmark.
/// - Shows today's Doses from the Scheduler (each with a checkmark).
/// - Notifications:
///     • Appointments: 1 day before, and 30 minutes before (name + type emoji + location)
///     • Doses: at time; if not ticked, follow-up in 15 minutes with "Did you take your med?"
///       Dose notifications include a "Done" action to tick from outside the app.
struct TodayView: View {
    @EnvironmentObject var settings: AppSettings

    // Repos (match the ones used in Schedule)
    @StateObject private var medsRepo = UserMedsRepo()
    @StateObject private var apptsRepo = AppointmentsRepo()

    // Today anchor (recomputed on appear)
    @State private var today: Date = Date()

    // Derived
    @State private var todaysDoses: [(Date, LocalMed)] = []

    // Completion state (persistent via UserDefaults so actions from notifications are reflected)
    @State private var completedAppointments: Set<String> = CompletionStore.completedAppointments()
    @State private var completedDoseKeys: Set<String> = CompletionStore.completedDoses()

    // Sheet state for viewing appointment details
    @State private var viewingAppointment: Appointment? = nil

    var body: some View {
        NavigationStack {
            List {
                // MARK: Appointments section
                Section(header: Text(sectionTitle("Appointments"))) {
                    appointmentsSection
                }

                // MARK: Doses section
                Section(header: Text(sectionTitle("Doses"))) {
                    dosesSection
                }

                // MARK: Notifications helper row (debug/visibility)
                Section {
                    Button("Reschedule Notifications for Today") {
                        Task { await scheduleNotificationsForToday() }
                    }
                } footer: {
                    Text("Appointments: a day before and 30 min before. Doses: at time; follow-up in 15 minutes if not ticked.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
            .onAppear {
                today = Calendar.current.startOfDay(for: Date())
                medsRepo.start()
                apptsRepo.start()
                recomputeDoses()

                // Refresh completion state (in case a background action toggled it)
                completedAppointments = CompletionStore.completedAppointments()
                completedDoseKeys = CompletionStore.completedDoses()

                Task { await NotificationsManager.shared.requestAuthorization()
                       await scheduleNotificationsForToday() }
            }
            .onChange(of: medsRepo.meds) { _, _ in
                recomputeDoses()
                Task { await scheduleNotificationsForToday() }
            }
            .onChange(of: settings.breakfast) { _, _ in changes() }
            .onChange(of: settings.lunch)     { _, _ in changes() }
            .onChange(of: settings.dinner)    { _, _ in changes() }
            .onChange(of: settings.bedtime)   { _, _ in changes() }
            .onChange(of: settings.wakeup)    { _, _ in changes() }
            // Detail sheet for appointments
            .sheet(item: $viewingAppointment) { appt in
                AppointmentDetailSheet(appointment: appt)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func changes() {
        recomputeDoses()
        Task { await scheduleNotificationsForToday() }
    }

    // MARK: - Appointments UI

    @ViewBuilder
    private var appointmentsSection: some View {
        if apptsRepo.isLoading {
            HStack { ProgressView(); Text("Loading appointments…") }
        } else if let err = apptsRepo.errorMessage {
            ContentUnavailableView("Couldn't load appointments",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(err))
        } else {
            let items = apptsRepo.appointments(on: today).sorted(by: { $0.date < $1.date })
            if items.isEmpty {
                ContentUnavailableView("No appointments today",
                                       systemImage: "calendar.badge.clock")
            } else {
                ForEach(items) { appt in
                    TodayRow(
                        isDone: completedAppointments.contains(appt.id),
                        leadingIcon: "", // title already includes emoji via titleWithEmoji
                        title: appt.titleWithEmoji,
                        subtitle: apptSubtitle(appt),
                        timeText: timeOnly(appt.date),
                        toggle: {
                            toggleAppointment(appt.id)
                        },
                        onTap: { viewingAppointment = appt }
                    )
                }
            }
        }
    }

    // MARK: - Doses UI

    @ViewBuilder
    private var dosesSection: some View {
        if medsRepo.isLoading {
            HStack { ProgressView(); Text("Loading medications…") }
        } else if let err = medsRepo.errorMessage {
            ContentUnavailableView("Couldn't load medications",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(err))
        } else if todaysDoses.isEmpty {
            ContentUnavailableView("No doses scheduled today",
                                   systemImage: "pills")
        } else {
            ForEach(todaysDoses.indices, id: \.self) { i in
                let (time, med) = todaysDoses[i]
                let key = doseKey(time: time, medID: med.id)

                TodayRow(
                    isDone: completedDoseKeys.contains(key),
                    leadingIcon: "💊",
                    title: med.name,
                    subtitle: "\(med.dosage) • \(foodRuleLabel(med.foodRule))",
                    timeText: time.formatted(date: .omitted, time: .shortened),
                    toggle: {
                        toggleDose(key)
                        // Cancel 15-min follow-up if user ticks in-app
                        NotificationsManager.shared.cancel(ids: ["DOSE_FU_\(key)"])
                    },
                    onTap: {
                        // For now, tapping dose toggles done
                        toggleDose(key)
                        NotificationsManager.shared.cancel(ids: ["DOSE_FU_\(key)"])
                    }
                )
            }
        }
    }

    // MARK: - Build Doses for today

    private func recomputeDoses() {
        guard medsRepo.isSignedIn else {
            todaysDoses = []
            return
        }

        let active = medsRepo.meds.filter { med in
            guard !med.isArchived else { return false }
            return (med.startDate ... med.endDate).contains(today)
        }
        guard !active.isEmpty else {
            todaysDoses = []
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
            date: today
        )

        let byId: [String: LocalMed] = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let display: [(Date, LocalMed)] = pairs.compactMap { (t, med) in
            guard let local = byId[med.id] else { return nil }
            return (t, local)
        }
        todaysDoses = display.sorted { $0.0 < $1.0 }
    }

    // MARK: - Notifications (for *today*)

    private func scheduleNotificationsForToday() async {
        // Ask permission (safe to call repeatedly)
        _ = await NotificationsManager.shared.requestAuthorization()

        // Build IDs and cancel existing to prevent duplicates
        let idsToCancel = buildAllNotificationIDsForToday()
        NotificationsManager.shared.cancel(ids: idsToCancel)

        // Appointments: schedule one day before + 30 minutes before (future only)
        let appts = apptsRepo.appointments(on: today)
        for appt in appts {
            let t = appt.date
            let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: t) ?? t
            let thirtyBefore = t.addingTimeInterval(-30 * 60)

            let title = "Appointment: \(appt.titleWithEmoji)"
            var body = timeOnly(t)
            if let loc = appt.location, !loc.isEmpty { body += " • \(loc)" }

            // IDs: APPT_1D_<id> and APPT_30_<id>
            NotificationsManager.shared.schedule(
                id: "APPT_1D_\(appt.id)",
                title: title,
                body: body,
                at: dayBefore,
                categoryId: NotificationsManager.IDs.apptCategory,
                userInfo: ["appointmentId": appt.id]
            )
            NotificationsManager.shared.schedule(
                id: "APPT_30_\(appt.id)",
                title: title,
                body: body,
                at: thirtyBefore,
                categoryId: NotificationsManager.IDs.apptCategory,
                userInfo: ["appointmentId": appt.id]
            )
        }

        // Doses: at time + follow-up 15 minutes later (if not completed)
        for (time, med) in todaysDoses {
            let key = doseKey(time: time, medID: med.id)
            let title = "Time to take \(med.name)"
            let body = "\(med.dosage) • \(foodRuleLabel(med.foodRule))"

            // Main dose ping
            NotificationsManager.shared.schedule(
                id: "DOSE_\(key)",
                title: title,
                body: body,
                at: time,
                categoryId: NotificationsManager.IDs.doseCategory,
                userInfo: ["doseKey": key]
            )

            // Follow-up (only schedule if not already completed)
            if !completedDoseKeys.contains(key) {
                let fu = time.addingTimeInterval(15 * 60)
                NotificationsManager.shared.schedule(
                    id: "DOSE_FU_\(key)",
                    title: "Did you take your med?",
                    body: "\(med.name) — \(med.dosage)",
                    at: fu,
                    categoryId: NotificationsManager.IDs.doseCategory,
                    userInfo: ["doseKey": key]
                )
            }
        }
    }

    private func notificationID(kind: String, key: String) -> String { "\(kind)_\(key)" }

    private func buildAllNotificationIDsForToday() -> [String] {
        var ids: [String] = []
        for appt in apptsRepo.appointments(on: today) {
            ids.append("APPT_1D_\(appt.id)")
            ids.append("APPT_30_\(appt.id)")
        }
        for (time, med) in todaysDoses {
            let key = doseKey(time: time, medID: med.id)
            ids.append("DOSE_\(key)")
            ids.append("DOSE_FU_\(key)")
        }
        return ids
    }

    // MARK: - Completion toggles

    private func toggleAppointment(_ id: String) {
        if completedAppointments.contains(id) {
            completedAppointments.remove(id)
        } else {
            completedAppointments.insert(id)
        }
        CompletionStore.setCompletedAppointments(completedAppointments)
    }

    private func toggleDose(_ key: String) {
        if completedDoseKeys.contains(key) {
            completedDoseKeys.remove(key)
        } else {
            completedDoseKeys.insert(key)
        }
        CompletionStore.setCompletedDoses(completedDoseKeys)
    }

    // MARK: - Helpers

    private func apptSubtitle(_ appt: Appointment) -> String {
        var parts: [String] = []
        if let loc = appt.location, !loc.isEmpty { parts.append(loc) }
        if let notes = appt.notes, !notes.isEmpty { parts.append(notes) }
        return parts.isEmpty ? "" : parts.joined(separator: " • ")
    }

    private func sectionTitle(_ base: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return "\(base) – \(df.string(from: today))"
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

    /// Stable unique key for a dose row (per med per time)
    private func doseKey(time: Date, medID: String) -> String {
        "\(medID)_\(Int(time.timeIntervalSince1970))"
    }
}

// MARK: - Reusable "Today" row with a tick and tap
private struct TodayRow: View {
    let isDone: Bool
    let leadingIcon: String
    let title: String
    let subtitle: String
    let timeText: String
    let toggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? .green : .secondary)
                    .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")
            }
            .buttonStyle(.plain)

            if !leadingIcon.isEmpty {
                Text(leadingIcon)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Text(timeText)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(isDone ? .secondary : .primary)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Appointment detail sheet
private struct AppointmentDetailSheet: View {
    let appointment: Appointment

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(appointment.titleWithEmoji)
                            .font(.headline)
                        Spacer()
                    }
                    HStack {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text(timeAndDate(appointment.date))
                    }
                }
                if let loc = appointment.location, !loc.isEmpty {
                    Section("Location") {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                            Text(loc)
                        }
                    }
                }
                if let notes = appointment.notes, !notes.isEmpty {
                    Section("Notes") { Text(notes) }
                }
            }
            .navigationTitle("Appointment")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func timeAndDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
