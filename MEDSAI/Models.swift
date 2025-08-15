import SwiftUI
import SwiftData

enum FoodRule: String, Codable, CaseIterable, Identifiable {
    case beforeFood, afterFood, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .beforeFood: return "Before food"
        case .afterFood:  return "After food"
        case .none:       return "No food rule"
        }
    }
}

@Model
final class Dose {
    var medID: String
    var scheduledAt: Date
    var status: DoseStatus
    
    init(medID: String, scheduledAt: Date, status: DoseStatus = .scheduled) {
        self.medID = medID
        self.scheduledAt = scheduledAt
        self.status = status
    }
}

@Model
final class Medication {
    @Attribute(.unique) var id: String
    var name: String
    var dosage: String
    var frequencyPerDay: Int
    var startDate: Date
    var endDate: Date
    var foodRule: FoodRule
    var notes: String?

    // NEW:
    var ingredients: [String]?        // e.g., ["metformin hydrochloride"]
    var minIntervalHours: Int?        // e.g., 12 (q12h)

    init(id: String = UUID().uuidString,
         name: String,
         dosage: String,
         frequencyPerDay: Int,
         startDate: Date,
         endDate: Date,
         foodRule: FoodRule = .none,
         notes: String? = nil,
         ingredients: [String]? = nil,
         minIntervalHours: Int? = nil) {
        self.id = id; self.name = name; self.dosage = dosage
        self.frequencyPerDay = frequencyPerDay
        self.startDate = startDate; self.endDate = endDate
        self.foodRule = foodRule; self.notes = notes
        self.ingredients = ingredients
        self.minIntervalHours = minIntervalHours
    }
}

enum DoseStatus: String, Codable { case scheduled, taken, missed }
