import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SearchHistoryRepo: ObservableObject {
    @Published private(set) var recent: [String] = []
    @Published private(set) var errorMessage: String?

    private var listener: ListenerRegistration?
    deinit { listener?.remove() }

    private var db: Firestore { Firestore.firestore() }

    private func requireUID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "SearchHistoryRepo",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User is not signed in."]
            )
        }
        return uid
    }

    /// Start streaming recent searches for the signed-in user (latest first).
    func start(limit: Int = 10) {
        listener?.remove(); listener = nil
        guard Auth.auth().currentUser != nil else { recent = []; return }

        do {
            let uid = try requireUID()
            listener = db.collection("users").document(uid)
                .collection("search_history")
                .order(by: "ts", descending: true)
                .limit(to: limit)
                .addSnapshotListener { [weak self] snap, err in
                    guard let self else { return }
                    if let err = err { self.errorMessage = err.localizedDescription; return }

                    let items = snap?.documents.compactMap { $0.data()["query"] as? String } ?? []

                    // Deduplicate while keeping order
                    var seen = Set<String>(); var out: [String] = []
                    for q in items {
                        let key = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if !key.isEmpty && !seen.contains(key) {
                            out.append(q); seen.insert(key)
                        }
                    }
                    self.recent = out
                }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Append a query to the user’s history (server timestamped).
    func add(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        do {
            let uid = try requireUID()
            let col = db.collection("users").document(uid).collection("search_history")
            try await col.addDocument(data: [
                "query": q,
                "ts": FieldValue.serverTimestamp()
            ])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
