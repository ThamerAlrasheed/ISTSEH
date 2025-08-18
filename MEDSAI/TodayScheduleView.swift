// TodayScheduleView.swift
import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Today (per-user meds via Firestore repo, local Dose checkmarks via SwiftData)

struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @EnvironmentObject var settings: AppSettings

    // Read the signed-in user's meds (same source Meds tab uses)
    @StateObject private var repo = UserMedsRepo()

    // We render Dose + its LocalMed
    @State private var todayDoses: [(Dose, LocalMed)] = []
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            Group {
                if !repo.isSignedIn {
                    ContentUnavailableView(
                        "Sign in required",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Please log in to see your daily schedule.")
                    )
                } else if repo.isLoading {
                    ProgressView("Building today’s schedule…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = repo.errorMessage {
                    ContentUnavailableView("Couldn’t load medications",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                } else {
                    List {
                        if todayDoses.isEmpty {
                            Text("No doses for today. Add a medication from the Meds tab.")
                                .foregroundStyle(.secondary)
                        } else {
                            Section("Schedule – \(todayDoses.count) dose\(todayDoses.count == 1 ? "" : "s")") {
                                ForEach(todayDoses.indices, id: \.self) { i in
                                    let (dose, med) = todayDoses[i]
                                    HStack {
                                        // Check button
                                        Button {
                                            toggle(dose)
                                        } label: {
                                            Image(systemName: dose.status == .taken ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(dose.status == .taken ? .green : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.trailing, 6)

                                        // Info
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(med.name).font(.headline)
                                            Text("\(med.dosage) • \(med.foodRule.label)")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(dose.scheduledAt.formatted(date: .omitted, time: .shortened))
                                            .font(.headline)
                                            .monospacedDigit()
                                            .foregroundStyle(dose.status == .taken ? .secondary : .primary)
                                    }
                                    .opacity(dose.status == .taken ? 0.6 : 1.0)
                                    .padding(.vertical, 4)

                                    // ⛔️ Removed swipeActions (no more slide-to-delete)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Today")
            .onAppear {
                repo.start()   // attach Firestore listener
                recompute()
            }
            // Rebuild when user meds change
            .onChange(of: repo.meds) { _, _ in recompute() }
            // Rebuild when user routine changes
            .onChange(of: settings.breakfast) { _, _ in recompute() }
            .onChange(of: settings.lunch)     { _, _ in recompute() }
            .onChange(of: settings.dinner)    { _, _ in recompute() }
            .onChange(of: settings.bedtime)   { _, _ in recompute() }
            .onChange(of: settings.wakeup)    { _, _ in recompute() }
            // Rebuild at midnight rollover
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
                if Calendar.current.isDate(date, inSameDayAs: now) == false {
                    now = date
                    recompute()
                }
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ dose: Dose) {
        dose.status = (dose.status == .taken ? .scheduled : .taken)
        try? ctx.save()
        // no need to recompute; UI updates from the model change
    }

    // MARK: - Build + upsert doses from Firestore meds

    private func recompute() {
        guard repo.isSignedIn else {
            todayDoses = []
            return
        }

        let cal = Calendar.current
        let today = Date()
        let startOfToday = cal.startOfDay(for: today)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)!

        // 1) Use only active, non-archived meds for today
        let activeMeds = repo.meds.filter { med in
            guard !med.isArchived else { return false }
            return (med.startDate ... med.endDate).contains(today)
        }

        // 2) Build (time, med) pairs for today
        let schedule = buildAdherenceSchedule(meds: activeMeds, settings: settings, date: today)

        // 3) Upsert Dose objects for today
        var fd = FetchDescriptor<Dose>(
            predicate: #Predicate { $0.scheduledAt >= startOfToday && $0.scheduledAt < startOfTomorrow }
        )
        fd.sortBy = [.init(\.scheduledAt, order: .forward)]
        let existing = (try? ctx.fetch(fd)) ?? []

        // quick lookup: medID+timestamp → Dose
        var index: [String: Dose] = [:]
        for d in existing {
            index["\(d.medID)|\(d.scheduledAt.timeIntervalSince1970)"] = d
        }

        var result: [(Dose, LocalMed)] = []
        for (time, med) in schedule {
            let key = "\(med.id)|\(time.timeIntervalSince1970)"
            if let d = index[key] {
                result.append((d, med))
            } else {
                let d = Dose(medID: med.id, scheduledAt: time, status: .scheduled)
                ctx.insert(d)
                result.append((d, med))
            }
        }

        try? ctx.save()
        todayDoses = result.sorted { $0.0.scheduledAt < $1.0.scheduledAt }
    }

    // MARK: - Scheduling helpers (simple, meal-aware slots)

    /// Build (time, med) for a single day using meal & sleep preferences.
    private func buildAdherenceSchedule(meds: [LocalMed], settings: AppSettings, date: Date) -> [(Date, LocalMed)] {
        var out: [(Date, LocalMed)] = []
        for med in meds {
            let times = timeSlots(for: med, settings: settings, on: date)
            for t in times {
                out.append((t, med))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    private func timeSlots(for med: LocalMed, settings: AppSettings, on date: Date) -> [Date] {
        let cal = Calendar.current
        let wake   = timeOn(date, from: settings.wakeup,  defaultHour: 7)
        let bed    = timeOn(date, from: settings.bedtime, defaultHour: 23)
        let bkfst  = timeOn(date, from: settings.breakfast, defaultHour: 8)
        let lunch  = timeOn(date, from: settings.lunch,     defaultHour: 13)
        let dinner = timeOn(date, from: settings.dinner,    defaultHour: 19)

        // If FDA text gave an interval (e.g. q12h), prefer that spacing within wake–bed window.
        if let intervalH = med.minIntervalHours, intervalH > 0 {
            var times: [Date] = []
            var t = max(wake, bkfst) // start around wake/breakfast
            while t <= bed && times.count < med.frequencyPerDay {
                times.append(t)
                if let next = cal.date(byAdding: .hour, value: intervalH, to: t) {
                    t = next
                } else {
                    break
                }
            }
            return times
        }

        // Otherwise map frequency to typical meal anchors
        switch med.frequencyPerDay {
        case ..<1:
            return []
        case 1:
            if med.foodRule == .afterFood { return [dinner] }
            if med.foodRule == .beforeFood { return [bkfst] }
            return [bkfst]
        case 2:
            return [bkfst, dinner]
        case 3:
            return [bkfst, lunch, dinner]
        default:
            let count = min(max(med.frequencyPerDay, 4), 6)
            return evenlySpaced(from: wake, to: bed, count: count)
        }
    }

    private func timeOn(_ day: Date, from comps: DateComponents, defaultHour: Int) -> Date {
        let cal = Calendar.current
        let h = comps.hour ?? defaultHour
        let m = comps.minute ?? 0
        var base = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
        let start = cal.startOfDay(for: day)
        if base < start { base = start }
        return base
    }

    private func evenlySpaced(from start: Date, to end: Date, count: Int) -> [Date] {
        guard count > 1, end > start else { return [start] }
        let interval = end.timeIntervalSince(start) / Double(count - 1)
        return (0..<count).map { i in start.addingTimeInterval(Double(i) * interval) }
    }
}

// MARK: - Optional: Today settings screen (unchanged)

struct TodaySettingsView: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    RoutinePickers()
                }
            }
            .navigationTitle("Settings")
        }
    }
}
