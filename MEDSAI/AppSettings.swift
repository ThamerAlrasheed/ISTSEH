import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // User profile
    @Published var firstName: String
    @Published var lastName: String
    @Published var dateOfBirth: Date?

    // Routine (meals & sleep)
    @Published var breakfast: DateComponents
    @Published var lunch: DateComponents
    @Published var dinner: DateComponents
    @Published var bedtime: DateComponents
    @Published var wakeup: DateComponents

    // App flow flags
    @Published var onboardingCompleted: Bool
    @Published var didChooseEntry: Bool

    private init() {
        // Profile defaults
        firstName = ""
        lastName  = ""
        dateOfBirth = nil

        // Routine defaults
        breakfast = DateComponents(hour: 8, minute: 0)
        lunch     = DateComponents(hour: 13, minute: 0)
        dinner    = DateComponents(hour: 19, minute: 0)
        bedtime   = DateComponents(hour: 23, minute: 0)
        wakeup    = DateComponents(hour: 7, minute: 0)

        // Flow defaults
        onboardingCompleted = false
        didChooseEntry = false
    }
}
