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
        self.firstName = ""
        self.lastName  = ""
        self.dateOfBirth = nil

        // Routine defaults
        self.breakfast = DateComponents(hour: 8, minute: 0)
        self.lunch     = DateComponents(hour: 13, minute: 0)
        self.dinner    = DateComponents(hour: 19, minute: 0)
        self.bedtime   = DateComponents(hour: 23, minute: 0)
        self.wakeup    = DateComponents(hour: 7, minute: 0)

        // Flow defaults
        self.onboardingCompleted = false
        self.didChooseEntry = false
    }

    // Convenience to bounce back to Landing
    func resetAppFlow() {
        didChooseEntry = false
        onboardingCompleted = false
    }
}
