import Foundation
import UserNotifications

// MARK: - Small utilities

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

enum DosageUnit: String, CaseIterable, Identifiable {
    case mg = "mg", g = "g", mL = "mL"
    var id: String { rawValue }
    var label: String { rawValue }
}

extension NumberFormatter {
    static let dosage: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        return f
    }()
}

func parseDosageToDouble(_ s: String) -> (Double?, DosageUnit) {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let amtStr = parts.first.map(String.init) ?? ""
    let unitStr = parts.count > 1 ? String(parts[1]).lowercased() : "mg"
    let unit = DosageUnit.allCases.first { $0.rawValue.lowercased() == unitStr } ?? .mg
    let num = NumberFormatter.dosage.number(from: amtStr)?.doubleValue
    return (num, unit)
}

func formatDosage(amount: Double, unit: DosageUnit) -> String {
    let s = NumberFormatter.dosage.string(from: NSNumber(value: amount)) ?? "\(amount)"
    return "\(s) \(unit.rawValue)"
}

// MARK: - Scheduler v2 (awake-window aware + meal anchoring + FDA interval)

enum Scheduler {

    // Tunables
    private static let afterFoodMinutes  = 30       // schedule ~30m after meals
    private static let beforeFoodMinutes = -45      // schedule ~45m before meals
    private static let defaultMinGapSec: TimeInterval = 15 * 60
    private static let mergeWindowSec: TimeInterval   = 10 * 60

    // Gentle edge padding for normal (no-food-rule) meds
    private static let normalAfterWakePadMin: Int = 15
    private static let normalBeforeBedPadMin: Int = 15
    private static let edgeEqualityLeewaySec: TimeInterval = 120

    /// Public entry — returns the (time, med) pairs for the given day.
    static func buildAdherenceSchedule(
        meds: [Medication],
        settings: AppSettings,
        date: Date = Date()
    ) -> [(Date, Medication)] {

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        // Only meds active today
        let active = meds.filter { $0.startDate <= endOfDay && $0.endDate >= startOfDay }
        if active.isEmpty { return [] }

        // 1) Build preferred anchors per med (already clamped to awake window)
        var pendingDoses: [(Date, Medication)] = []
        for m in active {
            for t in preferredTimes(for: m, on: startOfDay, settings: settings) {
                if t >= startOfDay && t < endOfDay { pendingDoses.append((t, m)) }
            }
        }

        // 2) Greedy clustering to reduce unique events while respecting co-scheduling rules
        var slots: [(time: Date, meds: [Medication])] = []
        for (t, m) in pendingDoses.sorted(by: { $0.0 < $1.0 }) {
            if let idx = bestSlotIndex(for: (t, m), in: slots) {
                slots[idx].meds.append(m)
                slots[idx].time = averageTime(slots[idx].time, t) // compact the slot a bit
            } else {
                slots.append((t, [m]))
            }
        }

        // 3) Enforce separation between slots if there are cross-slot conflicts
        slots = enforceInterSlotSeparation(slots)

        // 4) Expand
        return slots
            .sorted { $0.time < $1.time }
            .flatMap { slot in slot.meds.map { (slot.time, $0) } }
    }

    // MARK: Preferred anchors (per med)

    private static func preferredTimes(for med: Medication, on startOfDay: Date, settings: AppSettings) -> [Date] {
        let cal = Calendar.current

        func time(_ comps: DateComponents) -> Date {
            cal.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: startOfDay)!
        }

        // Build key times for the selected date
        let breakfast = time(settings.breakfast)
        let lunch     = time(settings.lunch)
        let dinner    = time(settings.dinner)
        let wake      = time(settings.wakeup)
        var bed       = time(settings.bedtime)

        // If bedtime is earlier than wake (after-midnight), push to next day gracefully
        if bed <= wake {
            bed = cal.date(byAdding: .hour, value: 16, to: wake) ?? wake.addingTimeInterval(16 * 3600)
        }

        func shift(_ base: Date, minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

        func clampInsideAwake(_ date: Date) -> Date {
            if date < wake { return wake.addingTimeInterval(5 * 60) }
            if date > bed  { return bed.addingTimeInterval(-5 * 60) }
            return date
        }

        switch med.foodRule {
        case .afterFood:
            var anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [dinner]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return Array(anchors.prefix(med.frequencyPerDay))
                .map { shift($0, minutes: afterFoodMinutes) }
                .map(clampInsideAwake)

        case .beforeFood:
            var anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [breakfast]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return Array(anchors.prefix(med.frequencyPerDay))
                .map { shift($0, minutes: beforeFoodMinutes) }
                .map(clampInsideAwake)

        case .none:
            // Evenly across the awake window; honor minIntervalHours if present.
            // If a time lands exactly on wake/bed, nudge: +15m after wake, −15m before bed.
            let raw = evenlySpaced(
                count: med.frequencyPerDay,
                from: wake,
                to: bed,
                minSpacingHours: med.minIntervalHours
            )

            let nudged = raw.map { t -> Date in
                var out = t
                if abs(t.timeIntervalSince(wake)) <= edgeEqualityLeewaySec {
                    out = wake.addingTimeInterval(TimeInterval(normalAfterWakePadMin * 60))
                } else if abs(t.timeIntervalSince(bed)) <= edgeEqualityLeewaySec {
                    out = bed.addingTimeInterval(TimeInterval(-normalBeforeBedPadMin * 60))
                }
                return clampInsideAwake(out)
            }
            return nudged
        }
    }

    private static func evenlySpaced(count: Int, from start: Date, to end: Date, minSpacingHours: Int?) -> [Date] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        let total = end.timeIntervalSince(start)
        var step  = total / Double(count - 1)
        if let minH = minSpacingHours { step = max(step, Double(minH) * 3600) }

        var out: [Date] = []
        var cursor = start
        out.append(cursor)
        for _ in 1..<(count) {
            cursor = cursor.addingTimeInterval(step)
            if let last = out.last, let minH = minSpacingHours {
                // Enforce minimum spacing
                let needed = last.addingTimeInterval(Double(minH) * 3600)
                if cursor < needed { cursor = needed }
            }
            // Cap at end
            if cursor > end { cursor = end }
            out.append(cursor)
        }
        return out
    }

    // MARK: Slotting / grouping

    private static func bestSlotIndex(for dose: (Date, Medication),
                                      in slots: [(time: Date, meds: [Medication])]) -> Int? {
        for i in slots.indices {
            let slot = slots[i]
            if abs(slot.time.timeIntervalSince(dose.0)) <= mergeWindowSec {
                if slot.meds.allSatisfy({ canCoSchedule($0, dose.1) }) {
                    return i
                }
            }
        }
        return nil
    }

    /// Can A and B be taken together? (via InteractionEngine rules)
    private static func canCoSchedule(_ a: Medication, _ b: Medication) -> Bool {
        let conflicts = InteractionEngine.checkConflicts(
            meds: [(a.name, a.ingredients ?? []), (b.name, b.ingredients ?? [])]
        )
        let hasAvoid   = conflicts.contains { if case .avoid = $0.kind { return true } else { return false } }
        let needsHours = conflicts.contains { if case .separate = $0.kind { return true } else { return false } }
        return !(hasAvoid || needsHours)
    }

    private static func enforceInterSlotSeparation(
        _ slots: [(time: Date, meds: [Medication])]
    ) -> [(time: Date, meds: [Medication])] {

        var out = slots.sorted { $0.time < $1.time }
        guard out.count > 1 else { return out }

        for i in 0..<out.count {
            for j in (i+1)..<out.count {
                let a = out[i], b = out[j]

                var maxHours: Double = 0
                var hasAvoid = false
                for ma in a.meds {
                    for mb in b.meds {
                        let conflicts = InteractionEngine.checkConflicts(
                            meds: [(ma.name, ma.ingredients ?? []), (mb.name, mb.ingredients ?? [])]
                        )
                        if conflicts.contains(where: { if case .avoid = $0.kind { return true } else { return false } }) {
                            hasAvoid = true
                        }
                        if let h = conflicts.compactMap({ c -> Double? in
                            if case .separate(let x) = c.kind { return x } else { return nil }
                        }).max() {
                            maxHours = max(maxHours, h)
                        }
                    }
                }

                // required gap
                let required = max(maxHours * 3600, hasAvoid ? defaultMinGapSec : defaultMinGapSec)

                if abs(a.time.timeIntervalSince(b.time)) < required {
                    // push the later slot forward
                    if a.time <= b.time {
                        out[j].time = a.time.addingTimeInterval(required)
                    } else {
                        out[i].time = b.time.addingTimeInterval(required)
                    }
                }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    // Utilities
    private static func averageTime(_ a: Date, _ b: Date) -> Date {
        let mid = (a.timeIntervalSinceReferenceDate + b.timeIntervalSinceReferenceDate) / 2
        return Date(timeIntervalSinceReferenceDate: mid)
    }
}

// MARK: - Local notifications

enum Notifier {
    static func requestAuth() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(local id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Summarization & bullet extraction

struct MedEssentials {
    let title: String
    let quickTips: [String]             // short chips at the top
    let whatFor: [String]               // “What it’s for”
    let howToTake: [String]             // “How to take”
    let commonSideEffects: [String]     // “Common side effects”
    let importantWarnings: [String]     // “Warnings — get help if…”
    let interactionsToAvoid: [String]   // “Don’t mix with”
    let ingredients: [String]
}

enum MedSummarizer {

    // Turn dense label text into short bullets
    static func bullets(from raw: String, max: Int = 5) -> [String] {
        // 0) Normalize whitespace & bullets
        var text = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression) // strip HTML tags
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "•", with: "\n• ")          // keep bullets as their own lines
            .replacingOccurrences(of: "·", with: "\n• ")
            .replacingOccurrences(of: "‣", with: "\n• ")
            .replacingOccurrences(of: "—", with: " – ")           // normalize long dash
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // 1) Remove big, shouty section headers like "1 INDICATIONS AND USAGE"
        text = text.replacingOccurrences(
            of: #"(^|\n)\s*\d+\s+[A-Z][A-Z\s/,-]{3,}(?=\n|$)"#,
            with: "",
            options: [.regularExpression]
        )

        // 2) Split into candidate lines (on bullets or sentence-ish boundaries)
        let candidates: [String] = text
            .replacingOccurrences(of: ".", with: ".\n")  // sentence newlines
            .replacingOccurrences(of: ";", with: ";\n")
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 3) Clean each line & keep only meaningful content
        var lines: [String] = []
        for var s in candidates {
            // drop leading bullet markers
            if s.hasPrefix("•") { s = s.dropFirst().trimmingCharacters(in: .whitespaces) }

            // remove orphan number lists like "(1)", "(1,2)", "2", "1 – 1"
            if s.range(of: #"^\(?\d+(?:\s*,\s*\d+)*\)?$"#, options: .regularExpression) != nil { continue }
            if s.range(of: #"^\d+\s*[–-]\s*\d+$"#, options: .regularExpression) != nil { continue }

            // remove bracketed numeric references occurring alone or at the start
            s = s.replacingOccurrences(of: #"^\(?\d+(?:,\s*\d+)*\)?\s*"#,
                                       with: "",
                                       options: .regularExpression)

            // prune very short / low-information lines
            if s.count < 8 { continue }

            // trim to ~140 chars at a natural boundary
            if s.count > 160 {
                let cut = s.index(s.startIndex, offsetBy: 140)
                if let space = s[cut...].firstIndex(of: " ") {
                    s = String(s[..<space])
                } else {
                    s = String(s.prefix(150))
                }
            }
            lines.append(s)
        }

        // 4) De-duplicate near-duplicates
        var out: [String] = []
        func similar(_ a: String, _ b: String) -> Bool {
            let ax = a.lowercased(), bx = b.lowercased()
            if ax == bx { return true }
            if ax.contains(bx) || bx.contains(ax) { return true }
            return false
        }
        for s in lines {
            if out.contains(where: { similar($0, s) }) { continue }
            out.append(s)
            if out.count >= max { break }
        }
        return out
    }

    static func essentials(from details: MedDetails) -> MedEssentials {
        let parsed = DrugTextParser.parse(details.combinedText)

        var tips: [String] = []
        if let fr = parsed.foodRule {
            tips.append(fr == .afterFood ? "Take after food" : "Take before food")
        }
        if let ih = parsed.minIntervalHours { tips.append("About every \(ih)h") }
        if !parsed.mustAvoid.isEmpty { tips.append("Avoid: " + parsed.mustAvoid.joined(separator: ", ")) }

        return MedEssentials(
            title: details.title,
            quickTips: tips,
            whatFor: bullets(from: details.uses, max: 4),
            howToTake: bullets(from: details.dosage, max: 5),
            commonSideEffects: bullets(from: details.sideEffects, max: 5),
            importantWarnings: bullets(from: details.warnings, max: 5),
            interactionsToAvoid: bullets(from: details.interactions, max: 4),
            ingredients: details.ingredients
        )
    }
}
