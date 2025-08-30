import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Firestore-backed repo for user appointments at:
/// users/{uid}/appointments
///
/// Fields:
/// - id: String (doc id)
/// - title: String
/// - type: String ("therapy", "doctor", "lab")
/// - date: Timestamp
/// - location: String?
/// - notes: String?
/// - createdAt / updatedAt: server timestamps
final class AppointmentsRepo: ObservableObject {
    @Published private(set) var items: [Appointment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    var isSignedIn: Bool { Auth.auth().currentUser != nil }

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else {
            items = []
            listener?.remove(); listener = nil
            return
        }
        isLoading = true
        errorMessage = nil

        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("appointments")
            .order(by: "date")

        listener?.remove()
        listener = ref.addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            self.isLoading = false
            if let err = err {
                self.errorMessage = err.localizedDescription
                return
            }
            let docs = snap?.documents ?? []
            self.items = docs.compactMap { Appointment.from(doc: $0) }
        }
    }

    func appointments(on date: Date) -> [Appointment] {
        let cal = Calendar.current
        return items.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    func add(title: String, type: AppointmentType, date: Date, location: String?, notes: String?, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "AppointmentsRepo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("appointments")
            .document()

        let payload: [String: Any] = [
            "title": title,
            "type": type.rawValue,
            "date": Timestamp(date: date),
            "location": location ?? "",
            "notes": notes ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        ref.setData(payload) { err in
            completion?(err)
        }
    }

    // MARK: - Update (for Edit)
    func update(id: String, title: String, type: AppointmentType, date: Date, location: String?, notes: String?, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "AppointmentsRepo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("appointments")
            .document(id)

        let payload: [String: Any] = [
            "title": title,
            "type": type.rawValue,
            "date": Timestamp(date: date),
            "location": location ?? "",
            "notes": notes ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ]

        ref.updateData(payload) { err in
            completion?(err)
        }
    }

    // MARK: - Delete
    @MainActor
    func delete(_ appointment: Appointment) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("appointments")
            .document(appointment.id)
        do {
            try await ref.delete()
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Appointment types (with emoji)

enum AppointmentType: String, CaseIterable, Identifiable {
    case therapy, doctor, lab
    var id: String { rawValue }

    var label: String {
        switch self {
        case .therapy: return "🧠 Therapy"
        case .doctor:  return "🩺 Doctor"
        case .lab:     return "🧪 Lab test"
        }
    }

    static func fromString(_ s: String?) -> AppointmentType {
        guard let s, let t = AppointmentType(rawValue: s) else { return .doctor }
        return t
    }
}

// MARK: - Model

struct Appointment: Identifiable, Equatable {
    let id: String
    let title: String
    let type: AppointmentType
    let date: Date
    let location: String?
    let notes: String?

    var titleWithEmoji: String { "\(type.label) • \(title)" }

    static func from(doc: QueryDocumentSnapshot) -> Appointment? {
        let data = doc.data()
        guard
            let title = data["title"] as? String,
            let ts = data["date"] as? Timestamp
        else { return nil }

        let type = AppointmentType.fromString(data["type"] as? String)
        let location = (data["location"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let notes = (data["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return Appointment(
            id: doc.documentID,
            title: title,
            type: type,
            date: ts.dateValue(),
            location: location,
            notes: notes
        )
    }
}
