import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Canonical model we store per medication (global, not per-user)
struct MedCatalogEntry: Codable, Identifiable {
    var id: String { key }          // document id = key
    let key: String                 // normalized key, e.g. "augmentin_500_mg" (or just name)
    var name: String                // last searched / chosen display name
    var aliases: [String]           // extra names the user tried (brand/generic)
    var imageURLs: [String]         // optional photo URLs (Storage or external)
    var payload: DrugPayload        // your in-app payload (camelCase)

    var createdAt: Date
    var updatedAt: Date

    init(key: String, name: String, aliases: [String] = [], imageURLs: [String] = [], payload: DrugPayload) {
        self.key = key
        self.name = name
        self.aliases = aliases
        self.imageURLs = imageURLs
        self.payload = payload
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init?(doc: DocumentSnapshot) {
        guard let data = doc.data() else { return nil }
        guard
            let key = data["key"] as? String,
            let name = data["name"] as? String,
            let created = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updated = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let payloadData = data["payload"] as? [String: Any],
            let json = try? JSONSerialization.data(withJSONObject: payloadData),
            let payload = try? JSONDecoder().decode(DrugPayload.self, from: json)
        else { return nil }

        self.key = key
        self.name = name
        self.aliases = data["aliases"] as? [String] ?? []
        self.imageURLs = data["imageURLs"] as? [String] ?? []
        self.payload = payload
        self.createdAt = created
        self.updatedAt = updated
    }

    var asFirestore: [String: Any] {
        var payloadMap: [String: Any] = [:]
        if let data = try? JSONEncoder().encode(payload),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payloadMap = obj
        }
        return [
            "key": key,
            "name": name,
            "aliases": aliases,
            "imageURLs": imageURLs,
            "payload": payloadMap,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
        ]
    }
}

// MARK: - Repo for global medications catalog
final class MedCatalogRepo {
    static let shared = MedCatalogRepo()
    private init() {}

    private var db: Firestore { Firestore.firestore() }
    private var col: CollectionReference { db.collection("medications") } // GLOBAL collection

    /// Normalize user input to a stable key (safe for doc IDs)
    func normalizeKey(_ raw: String) -> String {
        let lower = raw.lowercased()
        let replaced = lower.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Read by key if present
    func fetch(key: String) async throws -> MedCatalogEntry? {
        let snap = try await col.document(key).getDocument()
        return snap.exists ? MedCatalogEntry(doc: snap) : nil
    }

    /// Upsert from payload + original name (and optional image URL)
    func upsert(from payload: DrugPayload, searchedName: String, imageURL: URL? = nil) async throws -> MedCatalogEntry {
        // Prefer payload.title; fallback to searched name
        let display = payload.title.isEmpty ? searchedName : payload.title
        let key = normalizeKey(display)

        var existing = try await fetch(key: key)
        var aliases = Set(existing?.aliases ?? [])
        if searchedName.caseInsensitiveCompare(display) != .orderedSame {
            aliases.insert(searchedName)
        }

        var images = Set(existing?.imageURLs ?? [])
        if let u = imageURL { images.insert(u.absoluteString) }

        let entry = MedCatalogEntry(
            key: key,
            name: display,
            aliases: Array(aliases),
            imageURLs: Array(images),
            payload: payload
        )

        try await col.document(key).setData(entry.asFirestore, merge: true)
        return entry
    }
}
