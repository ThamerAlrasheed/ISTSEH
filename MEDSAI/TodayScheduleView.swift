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

                                    // ⛔️ No swipe-to-delete here
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
        // UI updates from model change
    }

    // MARK: - Build + upsert doses from Firestore meds (ADVANCED SCHEDULER)

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

        // 2) Run the ADVANCED scheduler (Helpers.Scheduler) by adapting LocalMed -> Medication (keeping same IDs)
        let schedulePairs = buildAdvancedScheduleForToday(from: activeMeds, date: today)

        // 3) Upsert Dose objects for today (SwiftData)
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

        // Map back Medication.id -> LocalMed
        let byId: [String: LocalMed] = Dictionary(uniqueKeysWithValues: activeMeds.map { ($0.id, $0) })

        var result: [(Dose, LocalMed)] = []
        for (time, medId) in schedulePairs {
            guard let local = byId[medId] else { continue }
            let key = "\(local.id)|\(time.timeIntervalSince1970)"
            if let d = index[key] {
                result.append((d, local))
            } else {
                let d = Dose(medID: local.id, scheduledAt: time, status: .scheduled)
                ctx.insert(d)
                result.append((d, local))
            }
        }

        try? ctx.save()
        todayDoses = result.sorted { $0.0.scheduledAt < $1.0.scheduledAt }
    }

    /// Uses `Scheduler.buildAdherenceSchedule` (from Helpers.swift) by adapting LocalMed to Medication.
    /// Returns pairs of (scheduled time, medication id) for today.
    private func buildAdvancedScheduleForToday(from meds: [LocalMed], date: Date) -> [(Date, String)] {
        // Adapt LocalMed -> Medication with SAME IDs for round-trip mapping
        let adapted: [Medication] = meds.map { m in
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

        // Advanced scheduler returns (Date, Medication). We only need (Date, id).
        let advanced = Scheduler.buildAdherenceSchedule(
            meds: adapted,
            settings: settings,
            date: date
        )
        return advanced.map { ($0.0, $0.1.id) }
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
