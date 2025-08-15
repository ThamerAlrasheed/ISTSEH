import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var meds: [Medication]
    @EnvironmentObject var settings: AppSettings

    // We render Dose + its Medication
    @State private var todayDoses: [(Dose, Medication)] = []
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            List {
                if todayDoses.isEmpty {
                    Text("No doses today yet. Add a medication.")
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
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    ctx.delete(dose)
                                    try? ctx.save()
                                    recompute()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .onAppear { recompute() }
            .onChange(of: meds)              { _, _ in recompute() }
            .onChange(of: settings.breakfast){ _, _ in recompute() }
            .onChange(of: settings.lunch)    { _, _ in recompute() }
            .onChange(of: settings.dinner)   { _, _ in recompute() }
            .onChange(of: settings.bedtime)  { _, _ in recompute() }
            .onChange(of: settings.wakeup)   { _, _ in recompute() }
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

    // MARK: - Build + upsert doses

    private func recompute() {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)!

        // 1) Build schedule (time + med)
        let schedule = Scheduler.buildAdherenceSchedule(meds: meds, settings: settings, date: Date())

        // 2) Upsert Dose objects for today
        // Fetch today’s existing doses once
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

        var result: [(Dose, Medication)] = []
        for (time, med) in schedule {
            let key = "\(med.id)|\(time.timeIntervalSince1970)"
            if let d = index[key] {
                result.append((d, med))
            } else {
                // create new scheduled dose
                let d = Dose(medID: med.id, scheduledAt: time, status: .scheduled)
                ctx.insert(d)
                result.append((d, med))
            }
        }

        try? ctx.save()

        // 3) Present sorted for UI
        todayDoses = result.sorted { $0.0.scheduledAt < $1.0.scheduledAt }
    }
}


// Weekly schedule placeholder (kept)
struct ScheduleView: View {
    var body: some View {
        NavigationStack {
            Text("Weekly schedule coming soon")
                .foregroundStyle(.secondary)
                .navigationTitle("Schedule")
        }
    }
}

struct ScanView: View {
    var body: some View {
        NavigationStack {
            Text("Scan (OCR) coming soon")
                .foregroundStyle(.secondary)
                .navigationTitle("Scan")
        }
    }
}

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
