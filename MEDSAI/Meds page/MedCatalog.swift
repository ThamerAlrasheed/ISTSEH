import Foundation

// MARK: - Canonical model we store per medication (global, not per-user)
struct MedCatalogEntry: Codable, Identifiable {
    var id: String { key }
    let key: String
    var name: String
    var aliases: [String]
    var imageURLs: [String]
    var payload: DrugPayload

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
}

// MARK: - Repo for global medications catalog (backend-backed)
final class MedCatalogRepo {
    static let shared = MedCatalogRepo()
    private init() {}

    /// Normalize user input to a stable key
    func normalizeKey(_ raw: String) -> String {
        let lower = raw.lowercased()
        let replaced = lower.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Read by name if present
    func fetch(name: String) async throws -> MedCatalogEntry? {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let row: APIMedicationCatalogEntry
        do {
            row = try await BackendClient.shared.request("/medications/catalog/\(encodedName)")
        } catch {
            return nil
        }

        let payload = DrugPayload(
            title: row.name,
            strengths: [],
            dosageForms: [],
            foodRule: row.foodRule,
            minIntervalHours: row.minIntervalHours,
            ingredients: row.activeIngredients,
            indications: [],
            howToTake: row.howToUse.map { [$0] } ?? [],
            commonSideEffects: row.sideEffects,
            importantWarnings: [],
            interactionsToAvoid: row.contraindications,
            references: nil,
            kbKey: nil
        )

        return MedCatalogEntry(
            key: normalizeKey(row.name),
            name: row.name,
            payload: payload
        )
    }

    /// Upsert from payload + original name
    func upsert(from payload: DrugPayload, searchedName: String, imageURL: URL? = nil) async throws -> MedCatalogEntry {
        let display = payload.title.isEmpty ? searchedName : payload.title
        if let existing = try await fetch(name: display) {
            return existing
        }

        return MedCatalogEntry(
            key: normalizeKey(display),
            name: display,
            payload: payload
        )
    }
}
