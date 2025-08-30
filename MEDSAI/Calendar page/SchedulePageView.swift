import SwiftUI

/// Calendar page with "fade-after-appointments" behavior:
/// - Calendar header stays fully visible while you scroll through Appointments.
/// - As soon as you reach Doses, the calendar slowly fades out.
/// - Scrolling back up reveals it again.
/// - App logic unchanged (appointments above doses unless no doses; centered Add button; 3-dot menu).
struct SchedulePageView: View {
    @EnvironmentObject var settings: AppSettings

    // Medications (same repo used by Today)
    @StateObject private var repo = UserMedsRepo()

    // Appointments Firestore repo
    @StateObject private var appts = AppointmentsRepo()

    // Selected calendar day
    @State private var selectedDate: Date = Date()

    // Read-only list of (time, LocalMed) pairs for the day
    @State private var dayDoses: [(Date, LocalMed)] = []

    // Sheets
    @State private var showAddAppointment = false
    @State private var editingAppointment: Appointment? = nil // presented via .sheet(item:)

    // Header measuring
    @State private var headerHeight: CGFloat = 240
    @State private var measuredHeaderOnce = false

    // Scrolling + fade control
    @State private var scrollOffset: CGFloat = 0          // top content scroll
    @State private var appointmentsHeight: CGFloat = 0    // measured total height of appointments block
    @State private var fadeProgress: CGFloat = 0          // 0..1 (0 visible, 1 fully faded)

    // Tunables
    private let fadeDistance: CGFloat = 220               // how many points from end-of-appointments until fully faded
    private let fadeAnimation = Animation.easeInOut(duration: 0.35)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                // SCROLL CONTENT
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {

                        // Offset tracker at the very top of the scroll content
                        GeometryReader { proxy in
                            let y = -proxy.frame(in: .named("ScheduleScroll")).minY
                            Color.clear.preference(key: ScrollOffsetKey.self, value: y)
                        }
                        .frame(height: 0)

                        // ----- PAGE CONTENT -----
                        VStack(spacing: 24) {

                            if dayDoses.isEmpty {
                                // Doses only (no appointments shown)
                                SectionCard {
                                    SectionHeader(title: sectionTitle("Doses"))
                                    VStack(spacing: 12) {
                                        ContentUnavailableView("No doses on this day",
                                                               systemImage: "calendar.badge.exclamationmark")
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                            } else {
                                // Appointments block (measured for fade trigger)
                                appointmentsBlock
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear
                                                .preference(key: AppointmentsHeightKey.self,
                                                            value: proxy.size.height)
                                        }
                                    )

                                // Doses block
                                dosesBlock
                            }
                        }
                        .padding(.bottom, 24)
                        // Reserve space at the top for the overlay header so content starts below it
                        .padding(.top, headerHeight)
                    }
                }
                .coordinateSpace(name: "ScheduleScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    // Update general scroll position
                    withAnimation(fadeAnimation) { scrollOffset = value }
                    updateFadeProgress()
                }
                .onPreferenceChange(AppointmentsHeightKey.self) { h in
                    appointmentsHeight = h
                    updateFadeProgress()
                }

                // OVERLAYING CALENDAR HEADER (fades after appointments)
                FadingHeader(
                    selectedDate: $selectedDate,
                    headerHeight: $headerHeight,
                    measuredOnce: $measuredHeaderOnce,
                    fadeProgress: fadeProgress
                )
            }
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
            // Add sheet
            .sheet(isPresented: $showAddAppointment) {
                AddAppointmentView(repo: appts, defaultDate: selectedDate, existing: nil)
            }
            // Edit sheet (uses Appointment as Identifiable)
            .sheet(item: $editingAppointment) { appt in
                AddAppointmentView(repo: appts, defaultDate: selectedDate, existing: appt)
            }
        }
    }

    // Compute fade progress: start fading once we've scrolled past the entire Appointments block.
    private func updateFadeProgress() {
        // If there are no doses, never fade the header.
        guard !dayDoses.isEmpty else {
            withAnimation(fadeAnimation) { fadeProgress = 0 }
            return
        }

        // Start fading when scrollOffset exceeds appointmentsHeight (i.e., when Doses reach the top area).
        let start = appointmentsHeight
        let delta = max(0, scrollOffset - start)          // how far past the end of appointments
        let p = min(1, delta / max(1, fadeDistance))      // normalize over fadeDistance
        withAnimation(fadeAnimation) { fadeProgress = p }
    }

    // MARK: - Appointments block (above doses when doses exist)
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

    // MARK: - Doses block (read-only)
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

        // Re-evaluate fade immediately when dose set flips between empty/non-empty
        updateFadeProgress()
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

// MARK: - Fading Header (calendar)
private struct FadingHeader: View {
    @Binding var selectedDate: Date
    @Binding var headerHeight: CGFloat
    @Binding var measuredOnce: Bool

    /// 0 = fully visible, 1 = fully faded
    let fadeProgress: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            CalendarView(selection: $selectedDate, initialMode: .monthly)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                headerHeight = proxy.size.height
                                measuredOnce = true
                            }
                            .onChange(of: proxy.size.height) { _, newValue in
                                headerHeight = newValue
                            }
                    }
                )
                .padding(.bottom, 8)
                .background(Color(.systemBackground))

            Divider()
        }
        .frame(height: headerHeight, alignment: .top)
        .opacity(1 - fadeProgress)
        .offset(y: -fadeProgress * 10) // tiny lift while fading (feel)
        .animation(.easeInOut(duration: 0.35), value: fadeProgress)
        .background(.ultraThinMaterial)
        .shadow(color: .black.opacity((1 - fadeProgress) > 0.02 ? 0.06 : 0), radius: 6, y: 4)
        .accessibilityHidden(fadeProgress >= 1)
        .opacity(measuredOnce ? (1 - fadeProgress) : 0) // avoid flash pre-measure
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

// MARK: - Preference keys
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AppointmentsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
