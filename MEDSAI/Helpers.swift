import Foundation
import UserNotifications

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


enum Scheduler {

    // Tunables
    private static let afterFoodMinutes  = 30
    private static let beforeFoodMinutes = -45
    private static let defaultMinGapSec: TimeInterval = 15 * 60   // 15 min
    private static let mergeWindowSec: TimeInterval   = 10 * 60   // if a slot is within 10 min, try to merge

    // MARK: Public entry
    static func buildAdherenceSchedule(
        meds: [Medication],
        settings: AppSettings,
        date: Date = Date()
    ) -> [(Date, Medication)] {

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        // Consider only meds active today
        let active = meds.filter { $0.startDate <= endOfDay && $0.endDate >= startOfDay }
        if active.isEmpty { return [] }

        // 1) Compute each med's *preferred* times for today
        var pendingDoses: [(Date, Medication)] = []
        for m in active {
            let anchors = preferredTimes(for: m, on: startOfDay, settings: settings)
            for t in anchors {
                // keep within today
                if t >= startOfDay && t < endOfDay { pendingDoses.append((t, m)) }
            }
        }

        // 2) Greedy clustering to MINIMIZE number of unique events:
        //    - try to put doses into existing slots if they are near in time AND co-takable
        //    - otherwise create a new slot for that dose
        var slots: [(time: Date, meds: [Medication])] = []
        for (t, m) in pendingDoses.sorted(by: { $0.0 < $1.0 }) {
            if let idx = bestSlotIndex(for: (t, m), in: slots) {
                // safe to co-schedule in this slot → group it
                slots[idx].meds.append(m)
                // move slot time slightly toward this dose to keep slots compact (average)
                let avg = averageTime(slots[idx].time, t)
                slots[idx].time = avg
            } else {
                // create new slot
                slots.append((t, [m]))
            }
        }

        // 3) Enforce separation rules *between* slots when there are conflicts across groups
        slots = enforceInterSlotSeparation(slots)

        // 4) Expand slots into (Date, Medication) for UI
        let result = slots
            .sorted { $0.time < $1.time }
            .flatMap { slot in slot.meds.map { (slot.time, $0) } }

        return result
    }

    // MARK: Preferred anchors for a single medication
    private static func preferredTimes(for med: Medication, on startOfDay: Date, settings: AppSettings) -> [Date] {
        let cal = Calendar.current
        func time(_ comps: DateComponents) -> Date {
            cal.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: startOfDay)!
        }

        let breakfast = time(settings.breakfast)
        let lunch     = time(settings.lunch)
        let dinner    = time(settings.dinner)
        let wake      = time(settings.wakeup)
        let bed       = time(settings.bedtime)

        func shift(_ base: Date, minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

        switch med.foodRule {
        case .afterFood:
            var anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [dinner]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return Array(anchors.prefix(med.frequencyPerDay)).map { shift($0, minutes: afterFoodMinutes) }

        case .beforeFood:
            var anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [breakfast]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return Array(anchors.prefix(med.frequencyPerDay)).map { shift($0, minutes: beforeFoodMinutes) }

        case .none:
            // evenly across wake window; honor minIntervalHours if present
            let start = wake
            let end   = bed > start ? bed : cal.date(byAdding: .hour, value: 16, to: start)! // safe fallback
            return evenlySpaced(count: med.frequencyPerDay, from: start, to: end, minSpacingHours: med.minIntervalHours)
        }
    }

    private static func evenlySpaced(count: Int, from start: Date, to end: Date, minSpacingHours: Int?) -> [Date] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        let total = end.timeIntervalSince(start)
        var step  = total / Double(count - 1)
        if let minH = minSpacingHours { step = max(step, Double(minH) * 3600) }
        return (0..<count).map { start.addingTimeInterval(Double($0) * step) }
    }

    // MARK: Slotting / grouping

    /// Find an existing slot we can merge into: close in time and co-takable with all meds already there.
    private static func bestSlotIndex(for dose: (Date, Medication),
                                      in slots: [(time: Date, meds: [Medication])]) -> Int? {
        for i in slots.indices {
            let slot = slots[i]
            // near in time?
            if abs(slot.time.timeIntervalSince(dose.0)) <= mergeWindowSec {
                // check coscheduling against everyone in the slot
                if slot.meds.allSatisfy({ canCoSchedule($0, dose.1) }) {
                    return i
                }
            }
        }
        return nil
    }

    /// Can A and B be taken together? (FDA rules via InteractionEngine)
    private static func canCoSchedule(_ a: Medication, _ b: Medication) -> Bool {
        let conflicts = InteractionEngine.checkConflicts(
            meds: [(a.name, a.ingredients ?? []), (b.name, b.ingredients ?? [])]
        )
        // If any "avoid" or "separate hours", we won't co-schedule
        let hasAvoid = conflicts.contains { if case .avoid = $0.kind { return true } else { return false } }
        let needsHours = conflicts.contains { if case .separate = $0.kind { return true } else { return false } }
        return !(hasAvoid || needsHours)
    }

    /// Ensure different slots obey separation requirements when their meds conflict.
    private static func enforceInterSlotSeparation(
        _ slots: [(time: Date, meds: [Medication])]
    ) -> [(time: Date, meds: [Medication])] {

        var out = slots.sorted { $0.time < $1.time }
        guard out.count > 1 else { return out }

        for i in 0..<out.count {
            for j in (i+1)..<out.count {
                let a = out[i], b = out[j]

                // derive the strongest rule between any pair across the two slots
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

import Foundation

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
    static func bullets(from text: String, max: Int = 5) -> [String] {
        // remove html tags + shrink whitespace
        let cleaned = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // split into sentences by ., ;, •, -  (very simple)
        let parts = cleaned
            .replacingOccurrences(of: "•", with: ".")
            .split(whereSeparator: { ".;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // keep concise lines; de‑jargon a tiny bit
        let simplified = parts
            .map { s -> String in
                var s = s
                s = s.replacingOccurrences(of: "contraindicated", with: "do not use")
                s = s.replacingOccurrences(of: "hypersensitivity", with: "allergic reaction")
                s = s.replacingOccurrences(of: "administer", with: "take")
                s = s.replacingOccurrences(of: "adverse reactions", with: "side effects")
                s = s.replacingOccurrences(of: "dosage and administration", with: "how to take")
                // shorten long lines
                if s.count > 140 {
                    let start = s.index(s.startIndex, offsetBy: min(120, s.count))
                    if let space = s[start...].firstIndex(of: " ") {
                        s = String(s.prefix(upTo: space))   // <-- key change
                    } else {
                        s = String(s.prefix(140))
                    }
                }
                return s
            }

        // remove near‑duplicates
        var out: [String] = []
        for line in simplified {
            if out.contains(where: { similar($0, line) }) { continue }
            out.append(line)
            if out.count >= max { break }
        }
        return out
    }

    // very lightweight duplicate check
    private static func similar(_ a: String, _ b: String) -> Bool {
        let la = a.lowercased(), lb = b.lowercased()
        if la == lb { return true }
        if la.contains(lb) || lb.contains(la) { return true }
        return false
    }

    static func essentials(from details: MedDetails) -> MedEssentials {
        // Parse quick rules from combined text
        let parsed = DrugTextParser.parse(details.combinedText)

        var tips: [String] = []
        if let fr = parsed.foodRule { tips.append(fr == .afterFood ? "Take after food" : "Take before food") }
        if let ih = parsed.minIntervalHours { tips.append("About every \(ih)h") }
        if !parsed.mustAvoid.isEmpty { tips.append("Avoid: " + parsed.mustAvoid.joined(separator: ", ")) }

        // Build sections as short bullets
        let whatFor      = bullets(from: details.uses, max: 4)
        let howToTake    = bullets(from: details.dosage, max: 5)
        let interactions = bullets(from: details.interactions, max: 4)
        let warnings     = bullets(from: details.warnings, max: 5)
        let sidefx       = bullets(from: details.sideEffects, max: 5)

        return MedEssentials(
            title: details.title,
            quickTips: tips,
            whatFor: whatFor,
            howToTake: howToTake,
            commonSideEffects: sidefx,
            importantWarnings: warnings,
            interactionsToAvoid: interactions,
            ingredients: details.ingredients
        )
    }
}

