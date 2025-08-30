import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // User profile (expand as needed)
    @Published var firstName: String
    @Published var lastName: String
    @Published var dateOfBirth: Date?

    // Routine (meals & sleep) – single source of truth for scheduling
    @Published var breakfast: DateComponents
    @Published var lunch: DateComponents
    @Published var dinner: DateComponents
    @Published var bedtime: DateComponents
    @Published var wakeup: DateComponents

    // App flow flags
    @Published var onboardingCompleted: Bool
    @Published var didChooseEntry: Bool

    // Internal
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingRemote = false
    private let saveDebounce = PassthroughSubject<Void, Never>()

    private init() {
        // Profile defaults
        firstName = ""
        lastName  = ""
        dateOfBirth = nil

        // Routine defaults (these are used until we load from Firestore)
        breakfast = DateComponents(hour: 8,  minute: 0)
        lunch     = DateComponents(hour: 13, minute: 0)
        dinner    = DateComponents(hour: 19, minute: 0)
        bedtime   = DateComponents(hour: 23, minute: 0)
        wakeup    = DateComponents(hour: 7,  minute: 0)

        // Flow defaults
        onboardingCompleted = false
        didChooseEntry = false

        // Debounced auto-save when routine changes locally
        saveDebounce
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.saveRoutineToFirestore() }
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
    }

    func resetAppFlow() {
        didChooseEntry = false
        onboardingCompleted = false
    }

    // MARK: - Firestore sync

    /// Call after sign-in (or app start if already signed in) to pull routine.
    func loadRoutineFromFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).getDocument { [weak self] snap, _ in
            guard let self, let data = snap?.data(), let routine = data["routine"] as? [String: Any] else { return }

            func comps(_ m: [String: Any]?, defaultHour: Int) -> DateComponents {
                DateComponents(hour: (m?["hour"] as? Int) ?? defaultHour,
                               minute: (m?["minute"] as? Int) ?? 0)
            }

            self.isApplyingRemote = true
            self.breakfast = comps(routine["breakfast"] as? [String: Any], defaultHour: 8)
            self.lunch     = comps(routine["lunch"]     as? [String: Any], defaultHour: 13)
            self.dinner    = comps(routine["dinner"]    as? [String: Any], defaultHour: 19)
            self.bedtime   = comps(routine["bedtime"]   as? [String: Any], defaultHour: 23)
            self.wakeup    = comps(routine["wakeup"]    as? [String: Any], defaultHour: 7)
            self.isApplyingRemote = false
        }
    }

    /// Debounced writer used whenever the user edits routine fields locally.
    func saveRoutineToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let routine: [String: Any] = [
            "breakfast": ["hour": breakfast.hour ?? 8, "minute": breakfast.minute ?? 0],
            "lunch":     ["hour": lunch.hour     ?? 13, "minute": lunch.minute     ?? 0],
            "dinner":    ["hour": dinner.hour    ?? 19, "minute": dinner.minute    ?? 0],
            "bedtime":   ["hour": bedtime.hour   ?? 23, "minute": bedtime.minute   ?? 0],
            "wakeup":    ["hour": wakeup.hour    ?? 7,  "minute": wakeup.minute    ?? 0]
        ]
        Firestore.firestore().collection("users").document(uid).setData(
            ["routine": routine, "updatedAt": FieldValue.serverTimestamp()],
            merge: true
        )
    }
}
