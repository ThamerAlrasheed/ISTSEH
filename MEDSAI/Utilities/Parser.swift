import Foundation

// What we extract from label text for scheduling hints
struct ParsedMedRules {
    var foodRule: FoodRule?
    var minIntervalHours: Int?
    var mustAvoid: [String]
}

enum DrugTextParser {

    // MARK: Public API (UNCHANGED)

    static func parse(_ raw: String) -> ParsedMedRules {
        let text = normalize(raw)

        // Food rule (before/after food / empty stomach)
        let food = parseFoodRule(text)

        // Minimum interval (q6h / every 6 hours / twice daily → 12h)
        let interval = parseIntervalHours(text)

        // Simple “avoid with” hints
        let avoid = parseAvoids(text)

        return ParsedMedRules(foodRule: food, minIntervalHours: interval, mustAvoid: avoid)
    }

    static func frequencySuggestion(from intervalHours: Int) -> Int {
        switch intervalHours {
        case 24: return 1
        case 12: return 2
        case 8:  return 3
        case 6:  return 4
        default: return max(1, min(6, Int(round(24.0 / Double(intervalHours)))))
        }
    }

    // MARK: - Normalization

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: "\n")
         .replacingOccurrences(of: "\n\n", with: "\n")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Food rule

    private static func parseFoodRule(_ text: String) -> FoodRule? {
        let lower = text.lowercased()

        // Strong phrases
        let afterHits = [
            "take after food", "take after a meal", "after meals", "after eating",
            "with meals", "with food", "administer with food", "take with food"
        ]
        if afterHits.contains(where: { lower.contains($0) }) { return .afterFood }

        let beforeHits = [
            "take before food", "before meals", "on an empty stomach", "1 hour before eating",
            "take on empty stomach", "administer on an empty stomach", "without food"
        ]
        if beforeHits.contains(where: { lower.contains($0) }) { return .beforeFood }

        // Section hints
        if lower.contains("dosage and administration") || lower.contains("instructions for use") {
            if lower.contains("with food") { return .afterFood }
            if lower.contains("empty stomach") || lower.contains("before food") { return .beforeFood }
        }
        return nil
    }

    // MARK: - Interval

    private static func parseIntervalHours(_ text: String) -> Int? {
        let t = text.lowercased()

        // q6h / q8h / q12h
        if let q = captureInt(#"(?:^|\b)q\s?(\d{1,2})\s?h\b"#, in: t) { return clamp(q) }

        // every 6 hours / at intervals of 6 hours
        if let hm = captureInt(#"(?:every|at intervals of)\s+(\d{1,2})\s*hours?"#, in: t) { return clamp(hm) }

        // every 4–6 hours (pick min)
        if let h = captureInt(#"\bevery\s+(\d{1,2})\s*(?:-|to|–|—)\s*(\d{1,2})\s*hours?\b"#, in: t, pick: .min) { return clamp(h) }

        // once/twice/three/four times daily
        if matches(#"\bonce\s+(?:daily|a\s+day)\b"#, t) { return 24 }
        if matches(#"\btwice\s+(?:daily|a\s+day)\b|\bbid\b"#, t) { return 12 }
        if matches(#"\bthree\s+times\s+(?:daily|a\s+day)\b|\btid\b"#, t) { return 8 }
        if matches(#"\bfour\s+times\s+(?:daily|a\s+day)\b|\bqid\b"#, t) { return 6 }

        // Phrases like “every morning” / “at bedtime” don’t imply a fixed gap
        return nil
    }

    private enum Pick { case min, max }
    private static func captureInt(_ pattern: String, in s: String, pick: Pick? = nil) -> Int? {
        do {
            let re = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let ns = s as NSString
            guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
            if m.numberOfRanges == 2, let r = Range(m.range(at: 1), in: s) {
                return Int(s[r])
            }
            if m.numberOfRanges >= 3, let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s) {
                let a = Int(s[r1]) ?? 0, b = Int(s[r2]) ?? 0
                return (pick == .max ? max(a,b) : min(a,b))
            }
            return nil
        } catch { return nil }
    }

    private static func clamp(_ v: Int?) -> Int? {
        guard let v, v > 0, v <= 24 else { return nil }
        return v
    }

    private static func matches(_ pattern: String, _ s: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .firstMatch(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count)) != nil
    }

    // MARK: - Avoids

    private static func parseAvoids(_ text: String) -> [String] {
        let lower = text.lowercased()
        var out: [String] = []

        let pairs: [(String, String)] = [
            ("grapefruit", "grapefruit"),
            ("alcohol", "alcohol"),
            ("antacids", "antacids"),
            ("maoi", "MAO inhibitors"),
            ("nsaids", "NSAIDs"),
            ("warfarin", "warfarin"),
            ("tetracycline", "tetracycline"),
            ("iron", "iron"),
            ("calcium", "calcium"),
            ("magnesium", "magnesium")
        ]

        for (needle, label) in pairs {
            if lower.contains(needle) { out.append(label) }
        }

        return Array(Set(out)).sorted()
    }
}
