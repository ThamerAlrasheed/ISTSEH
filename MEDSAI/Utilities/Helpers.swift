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

// MARK: - Scheduler

enum Scheduler {
    private static let afterFoodMinutes  = 30
    private static let beforeFoodMinutes = -45

    private static let normalAfterWakePadMin: Int = 15
    private static let normalBeforeBedPadMin: Int = 15
    private static let edgeEqualityLeewaySec: TimeInterval = 120

    static func buildAdherenceSchedule(
        meds: [Medication],
        settings: AppSettings,
        date: Date = Date()
    ) -> [(Date, Medication)] {

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        // Only meds active this day
        let active = meds.filter { $0.startDate <= endOfDay && $0.endDate >= startOfDay }
        guard !active.isEmpty else { return [] }

        var out: [(Date, Medication)] = []
        for m in active {
            let times = preferredTimes(for: m, on: startOfDay, settings: settings)
            for t in times { out.append((t, m)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    private static func preferredTimes(for med: Medication, on startOfDay: Date, settings: AppSettings) -> [Date] {
        let cal = Calendar.current

        func time(_ comps: DateComponents, day: Date) -> Date {
            cal.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: day)!
        }

        let breakfast = time(settings.breakfast, day: startOfDay)
        let lunch     = time(settings.lunch, day: startOfDay)
        let dinner    = time(settings.dinner, day: startOfDay)
        let wake      = time(settings.wakeup, day: startOfDay)
        var bed       = time(settings.bedtime, day: startOfDay)
        if bed <= wake {
            bed = cal.date(byAdding: .hour, value: 16, to: wake) ?? wake.addingTimeInterval(16 * 3600)
        }

        func shift(_ base: Date, minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

        // === full-day layout for 4+ doses, first dose at wake + 15min ===
        func fullDayExact(count: Int) -> [Date] {
            let step = 86400.0 / Double(count) // 24h / count
            let base = wake.addingTimeInterval(TimeInterval(normalAfterWakePadMin * 60)) // wake + 15min

            let j = Int(floor(max(0, base.timeIntervalSince(startOfDay)) / step))
            let anchor = startOfDay.addingTimeInterval(Double(j) * step)
            let delta  = base.timeIntervalSince(anchor)

            return (0..<count).map { i in
                startOfDay.addingTimeInterval(Double(i) * step + delta)
            }
        }

        switch med.foodRule {
        case .afterFood:
            var anchors: [Date]
            switch med.frequencyPerDay {
            case 1: anchors = [dinner]
            case 2: anchors = [breakfast, dinner]
            case 3: anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            var times = Array(anchors.prefix(min(med.frequencyPerDay, anchors.count)))
                .map { shift($0, minutes: afterFoodMinutes) }

            if med.frequencyPerDay > anchors.count {
                let step = TimeInterval(3 * 3600)
                var last = times.last ?? shift(dinner, minutes: afterFoodMinutes)
                while times.count < med.frequencyPerDay {
                    last = last.addingTimeInterval(step)
                    times.append(last)
                }
            }
            return times.map { t in
                var out = t
                if abs(t.timeIntervalSince(bed)) <= edgeEqualityLeewaySec {
                    out = bed.addingTimeInterval(TimeInterval(-normalBeforeBedPadMin * 60))
                }
                return out
            }

        case .beforeFood:
            var anchors: [Date]
            switch med.frequencyPerDay {
            case 1: anchors = [breakfast]
            case 2: anchors = [breakfast, dinner]
            case 3: anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            var times = Array(anchors.prefix(min(med.frequencyPerDay, anchors.count)))
                .map { shift($0, minutes: beforeFoodMinutes) }

            if med.frequencyPerDay > anchors.count {
                let step = TimeInterval(3 * 3600)
                var last = times.last ?? shift(breakfast, minutes: beforeFoodMinutes)
                while times.count < med.frequencyPerDay {
                    last = last.addingTimeInterval(step)
                    times.append(last)
                }
            }
            return times.map { t in
                var out = t
                if abs(t.timeIntervalSince(wake)) <= edgeEqualityLeewaySec {
                    out = wake.addingTimeInterval(TimeInterval(normalAfterWakePadMin * 60))
                }
                return out
            }

        case .none:
            if med.frequencyPerDay >= 4 {
                return fullDayExact(count: med.frequencyPerDay)
            } else {
                let baseStep = (bed.timeIntervalSince(wake)) / Double(max(med.frequencyPerDay - 1, 1))
                let step     = max(baseStep, 0)
                var times: [Date] = []
                for i in 0..<med.frequencyPerDay {
                    times.append(wake.addingTimeInterval(step * Double(i)))
                }
                return times.map { t in
                    var out = t
                    if abs(t.timeIntervalSince(wake)) <= edgeEqualityLeewaySec {
                        out = wake.addingTimeInterval(TimeInterval(normalAfterWakePadMin * 60))
                    } else if abs(t.timeIntervalSince(bed)) <= edgeEqualityLeewaySec {
                        out = bed.addingTimeInterval(TimeInterval(-normalBeforeBedPadMin * 60))
                    }
                    return out
                }
            }
        }
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
    let quickTips: [String]
    let whatFor: [String]
    let howToTake: [String]
    let commonSideEffects: [String]
    let importantWarnings: [String]
    let interactionsToAvoid: [String]
    let ingredients: [String]
}

enum MedSummarizer {
    static func bullets(from raw: String, max: Int = 5) -> [String] {
        var text = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "•", with: "\n• ")
            .replacingOccurrences(of: "·", with: "\n• ")
            .replacingOccurrences(of: "‣", with: "\n• ")
            .replacingOccurrences(of: "—", with: " – ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        text = text.replacingOccurrences(
            of: #"(^|\n)\s*\d+\s+[A-Z][A-Z\s/,-]{3,}(?=\n|$)"#,
            with: "",
            options: [.regularExpression]
        )

        let candidates: [String] = text
            .replacingOccurrences(of: ".", with: ".\n")
            .replacingOccurrences(of: ";", with: ";\n")
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var lines: [String] = []
        for var s in candidates {
            if s.hasPrefix("•") { s = s.dropFirst().trimmingCharacters(in: .whitespaces) }
            if s.range(of: #"^\(?\d+(?:\s*,\s*\d+)*\)?$"#, options: .regularExpression) != nil { continue }
            if s.range(of: #"^\d+\s*[–-]\s*\d+$"#, options: .regularExpression) != nil { continue }
            s = s.replacingOccurrences(of: #"^\(?\d+(?:,\s*\d+)*\)?\s*"#,
                                       with: "",
                                       options: .regularExpression)
            if s.count < 8 { continue }
            if s.count > 160 {
                let cut = s.index(s.startIndex, offsetBy: 140)
                if let space = s[cut...].firstIndex(of: " ") { s = String(s[..<space]) }
                else { s = String(s.prefix(150)) }
            }
            lines.append(s)
        }

        var out: [String] = []
        func similar(_ a: String, _ b: String) -> Bool {
            let ax = a.lowercased(), bx = b.lowercased()
            return ax == bx || ax.contains(bx) || bx.contains(ax)
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

