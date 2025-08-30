import Foundation

// What we extract from FDA text
struct ParsedMedRules {
    var foodRule: FoodRule?
    var minIntervalHours: Int?
    var mustAvoid: [String]
}

enum DrugTextParser {

    // MARK: - Public

    static func parse(_ raw: String) -> ParsedMedRules {
        let text = normalize(raw)

        // 1) Food rule
        let food = parseFoodRule(text)

        // 2) Interval (hours)  — prefers explicit numbers (e.g. “every 12 hours”, “q12h”)
        let interval = parseIntervalHours(text)

        // 3) Simple “avoid” list
        let avoid = parseAvoids(text)

        return ParsedMedRules(foodRule: food, minIntervalHours: interval, mustAvoid: avoid)
    }

    /// Convert an interval (e.g. q12h → 2/day) into a rough frequency suggestion
    static func frequencySuggestion(from intervalHours: Int) -> Int {
        switch intervalHours {
        case 24: return 1
        case 12: return 2
        case 8:  return 3
        case 6:  return 4
        default: return max(1, min(6, Int(round(24.0 / Double(intervalHours)))))
        }
    }

    // MARK: - Food rule

    private static func parseFoodRule(_ text: String) -> FoodRule? {
        // Positive (with/after food)
        let afterFoodPhrases: [String] = [
            "take with food",
            "with food",
            "with meals",
            "with a meal",
            "after food",
            "after a meal",
            "after meals",
            "immediately after food",
            "take with milk",           // some labels say “with food or milk”
            "take with food or milk",
        ]

        // Negative (no food / empty stomach / before meals)
        let beforeFoodPhrases: [String] = [
            "on an empty stomach",
            "take on an empty stomach",
            "without food",
            "before meals",
            "before food",
            "at least 1 hour before meals",
            "1 hour before or 2 hours after meals",
            "take at least 1 hour before or 2 hours after eating",
            "take 1 hour before or 2 hours after food",
        ]

        // If the label explicitly mentions BOTH, we bias toward “before food”
        // (those lines usually read like “take 1 hour before or 2 hours after meals”)
        let hasAfter  = containsAny(text, afterFoodPhrases)
        let hasBefore = containsAny(text, beforeFoodPhrases)

        if hasBefore { return .beforeFood }
        if hasAfter  { return .afterFood }

        // Regex variants
        // “… after (a)? meal(s)”
        if matches(#"\bafter\s+(?:a\s+)?meal[s]?\b"#, text) { return .afterFood }
        // “… before meal(s) / eating”
        if matches(#"\bbefore\s+(?:a\s+)?meal[s]?\b"#, text) { return .beforeFood }
        if matches(#"\bon\s+an?\s+empty\s+stomach\b"#, text) { return .beforeFood }

        return nil
    }

    // MARK: - Interval

    private static func parseIntervalHours(_ text: String) -> Int? {
        // Strongest signal: “every 12 hours”, “every 6 hrs”, “every 8h”
        if let h = captureInt(#"\bevery\s+(\d{1,2})\s*(?:hours?|hrs?|h)\b"#, in: text) { return h }

        // q12h / q 12 h / q12 hr
        if let h = captureInt(#"\bq\s*(\d{1,2})\s*(?:h|hr|hrs)\b"#, in: text) { return h }

        // Ranges like “every 8–12 hours” → we’ll take the **lower** bound (more conservative)
        if let h = captureInt(#"\bevery\s+(\d{1,2})\s*(?:-|to)\s*(\d{1,2})\s*(?:hours?|hrs?|h)\b"#, in: text, pick: .min) { return h }

        // Verbal frequencies
        if matches(#"\bonce\s+(?:daily|a\s+day)\b"#, text)          { return 24 }
        if matches(#"\btwice\s+(?:daily|a\s+day)\b|\bbid\b"#, text) { return 12 }
        if matches(#"\bthree\s+times\s+(?:daily|a\s+day)\b|\btid\b"#, text) { return 8 }
        if matches(#"\bfour\s+times\s+(?:daily|a\s+day)\b|\bqid\b"#, text)  { return 6 }

        // “every morning” / “at bedtime” doesn’t imply a fixed hour gap → leave nil
        return nil
    }

    // MARK: - Avoids

    private static func parseAvoids(_ text: String) -> [String] {
        // Common interactions users recognize
        let candidates: [(key: String, patterns: [String])] = [
            ("antacids",         ["antacid", "antacids"]),
            ("aluminum",         ["aluminum"]),
            ("magnesium",        ["magnesium"]),
            ("iron",             ["iron", "ferrous"]),
            ("calcium",          ["calcium"]),
            ("dairy",            ["dairy", "milk", "cheese", "yogurt"]),
            ("grapefruit",       ["grapefruit", "grapefruit juice"]),
            ("alcohol",          ["alcohol"]),
            ("zinc",             ["zinc"]),
            ("caffeine",         ["caffeine", "coffee"]),
            ("nsaids",           ["nsaid", "nsaids", "ibuprofen", "naproxen"]),
        ]

        var out: Set<String> = []
        for (label, pats) in candidates {
            // pick up phrases like “avoid …”, “do not take with …”, “separate from …”
            if pats.contains(where: { p in
                containsAny(text, [
                    "avoid \(p)", "do not take with \(p)", "do not use with \(p)",
                    "separate from \(p)", "separate administration from \(p)",
                    "separate by at least", "separate doses from \(p)"
                ]) && text.contains(p)
            }) {
                out.insert(label)
            } else if text.contains("avoid") && containsAny(text, pats) {
                out.insert(label)
            }
        }

        return out.sorted()
    }

    // MARK: - Helpers

    private static func normalize(_ raw: String) -> String {
        // Strip html, condense whitespace, lowercase
        raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        for n in needles where haystack.contains(n) { return true }
        return false
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
    }

    /// Returns Int from the first (or min/max) capture group(s) in a regex
    private enum Pick { case first, min, max }

    private static func captureInt(_ pattern: String, in text: String, pick: Pick = .first) -> Int? {
        do {
            let rx = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let m = rx.firstMatch(in: text, options: [], range: range) else { return nil }

            switch pick {
            case .first:
                guard m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: text),
                      let v = Int(text[r]) else { return nil }
                return v

            case .min, .max:
                guard m.numberOfRanges >= 3,
                      let r1 = Range(m.range(at: 1), in: text),
                      let r2 = Range(m.range(at: 2), in: text),
                      let v1 = Int(text[r1]), let v2 = Int(text[r2]) else { return nil }
                return pick == .min ? min(v1, v2) : max(v1, v2)
            }
        } catch {
            return nil
        }
    }
}
