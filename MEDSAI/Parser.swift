import Foundation

struct ParsedMedRules {
    var foodRule: FoodRule?
    var minIntervalHours: Int?
    var mustAvoid: [String]
}

enum DrugTextParser {

    static func parse(_ raw: String) -> ParsedMedRules {
        // normalize
        let text = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()

        // food rule
        let food: FoodRule? = {
            if text.contains("take with food") || text.contains("with meals") || text.contains("after food") || text.contains("after a meal") {
                return .afterFood
            }
            if text.contains("on an empty stomach") || text.contains("before food") || text.contains("before meals") {
                return .beforeFood
            }
            if text.contains("with food") { return .afterFood }
            return nil
        }()

        // interval (hours)
        let interval: Int? = {
            if let h = captureInt(#"every\s+(\d{1,2})\s*(?:hours?|hrs?|h)\b"#, in: text) { return h }
            if let h = captureInt(#"\bq\s*(\d{1,2})\s*h\b"#, in: text) { return h }
            if text.contains("once daily") || text.contains("once a day") { return 24 }
            if text.contains("twice daily") || text.contains("two times a day") || text.contains("bid") { return 12 }
            if text.contains("three times daily") || text.contains("tid") { return 8 }
            if text.contains("four times daily") || text.contains("qid") { return 6 }
            return nil
        }()

        // simple avoid hints
        var avoid: [String] = []
        let avoidWords = ["antacids","antacid","iron","calcium","dairy","milk","alcohol","grapefruit","magnesium","zinc","coffee"]
        for w in avoidWords {
            if text.contains("avoid \(w)") || text.contains("do not take with \(w)") || text.contains("separate from \(w)") {
                avoid.append(w)
            }
        }
        avoid = Array(Set(avoid)).sorted()

        return ParsedMedRules(foodRule: food, minIntervalHours: interval, mustAvoid: avoid)
    }

    static func frequencySuggestion(from intervalHours: Int) -> Int {
        switch intervalHours {
        case 6:  return 4
        case 8:  return 3
        case 12: return 2
        case 24: return 1
        default: return max(1, min(6, Int(round(24.0 / Double(intervalHours)))))
        }
    }

    // MARK: - Helpers
    /// Returns Int from first capture group of pattern, or nil
    private static func captureInt(_ pattern: String, in text: String) -> Int? {
        do {
            let rx = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let m = rx.firstMatch(in: text, options: [], range: range),
                  m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: text) else { return nil }
            return Int(text[r])
        } catch {
            return nil
        }
    }
}
