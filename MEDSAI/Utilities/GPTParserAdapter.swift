import Foundation

// Uses your existing FoodRule enum defined in Helpers.swift:
// enum FoodRule: String, Codable { case none, beforeFood, afterFood }
// plus any other helpers you already have.

extension DrugPayload {
    /// Map backend's "before_food"/"after_food"/"none" to your app enum.
    var foodRuleEnum: FoodRule {
        switch (foodRule ?? "none").lowercased() {
        case "afterfood", "after_food": return .afterFood
        case "beforefood", "before_food": return .beforeFood
        default: return .none
        }
    }

    /// Suggest frequency from minIntervalHours (like your DrugTextParser.frequencySuggestion)
    var suggestedFrequencyPerDay: Int {
        guard let h = minIntervalHours, h > 0 else { return 2 } // fallback
        return max(1, min(6, Int((24.0 / Double(h)).rounded())))
    }

    /// Short chip strings you can show under the title (mirrors what you did in Meds)
    var quickChips: [String] {
        var chips: [String] = []
        switch foodRuleEnum {
        case .afterFood: chips.append("Take after food")
        case .beforeFood: chips.append("Take before food")
        case .none: break
        }
        if let h = minIntervalHours { chips.append("~every \(h)h") }
        return chips
    }
}
