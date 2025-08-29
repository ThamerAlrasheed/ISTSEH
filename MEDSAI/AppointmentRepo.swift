import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Firestore-backed repo for user appointments at:
/// users/{uid}/appointments
///
/// Document fields:
/// - id: String (doc id)
/// - title: String
/// - date: Timestamp
/// - location: String?
/// - notes: String?
/// - createdAt / updatedAt: server timestamps
final class AppointmentsRepo: ObservableObject {
    @Published private(set) var items: [Appointment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    private var listener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()

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

    func add(title: String, date: Date, location: String?, notes: String?, completion: ((Error?) -> Void)? = nil) {
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
}

// MARK: - Model

struct Appointment: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date
    let location: String?
    let notes: String?

    static func from(doc: QueryDocumentSnapshot) -> Appointment? {
        let data = doc.data()
        guard
            let title = data["title"] as? String,
            let ts = data["date"] as? Timestamp
        else { return nil }

        let location = (data["location"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let notes = (data["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return Appointment(
            id: doc.documentID,
            title: title,
            date: ts.dateValue(),
            location: location,
            notes: notes
        )
    }
}
