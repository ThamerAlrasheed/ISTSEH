import Foundation
import SwiftUI
import Combine

enum UserRole: String, Codable {
    case regular, caregiver, patient
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // User profile (expand as needed)
    @Published var firstName: String
    @Published var lastName: String
    @Published var dateOfBirth: Date?
    
    // Caregiver Role (persisted to UserDefaults)
    @Published var role: UserRole {
        didSet { UserDefaults.standard.set(role.rawValue, forKey: "userRole") }
    }
    @Published var activePatientID: String? = nil // If caregiver, who are we viewing?
    @Published var familyMembers: [String] = []  // Names/IDs of linked patients

    // Routine (meals & sleep) – single source of truth for scheduling
    @Published var breakfast: DateComponents
    @Published var lunch: DateComponents
    @Published var dinner: DateComponents
    @Published var bedtime: DateComponents
    @Published var wakeup: DateComponents

    // App flow flags
    @Published var onboardingCompleted: Bool
    @Published var didChooseEntry: Bool

    // Appearance
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case light, dark, system
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    @Published var appearanceMode: AppearanceMode

    /// Returns the ColorScheme to pass to `.preferredColorScheme()`.
    /// `nil` means follow the system setting.
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    // Internal
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingRemote = false
    private let saveDebounce = PassthroughSubject<Void, Never>()

    private init() {
        // Profile defaults
        firstName = ""
        lastName  = ""
        dateOfBirth = nil

        // Restore persisted role
        let savedRole = UserDefaults.standard.string(forKey: "userRole") ?? UserRole.regular.rawValue
        role = UserRole(rawValue: savedRole) ?? .regular

        // Routine defaults (used until we load from the backend)
        breakfast = DateComponents(hour: 8,  minute: 0)
        lunch     = DateComponents(hour: 13, minute: 0)
        dinner    = DateComponents(hour: 19, minute: 0)
        bedtime   = DateComponents(hour: 23, minute: 0)
        wakeup    = DateComponents(hour: 7,  minute: 0)

        // Flow defaults
        onboardingCompleted = false
        didChooseEntry = false

        // Appearance default (light)
        let savedMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.light.rawValue
        appearanceMode = AppearanceMode(rawValue: savedMode) ?? .light

        // Debounced auto-save when routine changes locally
        saveDebounce
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in
                Task { [weak self] in await self?.saveRoutineToBackend() }
            }
            .store(in: &cancellables)

        // Watch routine fields
        Publishers.MergeMany(
            $breakfast.map { _ in () },
            $lunch.map { _ in () },
            $dinner.map { _ in () },
            $bedtime.map { _ in () },
            $wakeup.map { _ in () }
        )
        .sink { [weak self] in
            guard let self, !self.isApplyingRemote else { return }
            self.saveDebounce.send(())
        }
        .store(in: &cancellables)

        // Persist appearance mode
        $appearanceMode
            .dropFirst() // skip initial value
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "appearanceMode") }
            .store(in: &cancellables)
    }

    func resetAppFlow() {
        didChooseEntry = false
        onboardingCompleted = false
    }

    // MARK: - Backend sync

    /// Call after sign-in (or app start if already signed in) to pull the routine and profile from the backend.
    @MainActor
    func loadRoutineFromBackend() async {
        do {
            async let userTask = ProfileRepository.shared.fetchCurrentUser()
            async let routineTask = ProfileRepository.shared.fetchRoutine()
            let (user, routine) = try await (userTask, routineTask)

            isApplyingRemote = true
            breakfast = parseTime(routine.breakfastTime, defaultHour: 8)
            lunch     = parseTime(routine.lunchTime, defaultHour: 13)
            dinner    = parseTime(routine.dinnerTime, defaultHour: 19)
            bedtime   = parseTime(routine.bedtime, defaultHour: 23)
            wakeup    = parseTime(routine.wakeupTime, defaultHour: 7)

            firstName = user.firstName ?? ""
            lastName = user.lastName ?? ""
            dateOfBirth = APIFormatters.parseDate(user.dateOfBirth)
            role = UserRole(rawValue: user.role) ?? .regular

            isApplyingRemote = false
        } catch {
            print("⚠️ loadRoutineFromBackend failed:", error.localizedDescription)
            isApplyingRemote = false
        }
    }

    /// Debounced writer used whenever the user edits routine fields locally.
    func saveRoutineToBackend() async {
        do {
            _ = try await ProfileRepository.shared.updateRoutine(
                APIRoutineUpdateRequest(
                    breakfastTime: formatTime(breakfast, defaultHour: 8),
                    lunchTime: formatTime(lunch, defaultHour: 13),
                    dinnerTime: formatTime(dinner, defaultHour: 19),
                    bedtime: formatTime(bedtime, defaultHour: 23),
                    wakeupTime: formatTime(wakeup, defaultHour: 7)
                )
            )
        } catch {
            print("⚠️ saveRoutineToBackend failed:", error.localizedDescription)
        }
    }

    // MARK: - Time helpers

    /// Converts a Postgres TIME string like "08:00:00" into DateComponents.
    private func parseTime(_ timeString: String?, defaultHour: Int) -> DateComponents {
        guard let ts = timeString, ts.count >= 5 else {
            return DateComponents(hour: defaultHour, minute: 0)
        }
        let parts = ts.prefix(5).split(separator: ":")
        let hour = Int(parts.first ?? "") ?? defaultHour
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return DateComponents(hour: hour, minute: minute)
    }

    /// Converts DateComponents back to a Postgres TIME string like "08:00:00".
    private func formatTime(_ comps: DateComponents, defaultHour: Int) -> String {
        let h = comps.hour ?? defaultHour
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d:00", h, m)
    }
}
