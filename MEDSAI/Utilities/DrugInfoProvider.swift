import Foundation

// MARK: - Your existing, app-facing model (kept the same)
struct DrugPayload: Codable {
    let title: String
    let strengths: [String]
    let dosageForms: [String]        // backend doesn’t send this yet; we fill [] for now
    let foodRule: String?            // "afterFood" | "beforeFood" | "none"
    let minIntervalHours: Int?
    let ingredients: [String]        // backend doesn’t send ingredients yet; []
    let indications: [String]
    let howToTake: [String]
    let commonSideEffects: [String]
    let importantWarnings: [String]  // backend doesn’t send warnings yet; []
    let interactionsToAvoid: [String]
    let references: [String]?        // backend doesn’t send refs yet; nil
    let kbKey: String?               // reserved for future; server can add later
}

// MARK: - Protocol: unchanged
protocol DrugInfoProvider {
    static func fetchDetails(name: String) async throws -> DrugPayload
    static func fetchDosageOptions(name: String) async throws -> [String]
    static func analyzeImage(url: URL) async throws -> DrugPayload
}

// MARK: - Backend wire model (matches your Cloud Function JSON) — lenient decoding
private struct BackendPayload: Codable {
    let title: String?
    let strengths: [String]?
    let food_rule: String?
    let min_interval_hours: Int?
    let interactions_to_avoid: [String]?
    let common_side_effects: [String]?
    let how_to_take: [String]?
    let what_for: [String]?
}

// MARK: - HTTP client
enum DrugInfo: DrugInfoProvider {
    private struct DrugIntelRequestBody: Encodable {
        let name: String?
        let imageURL: String?

        enum CodingKeys: String, CodingKey {
            case name
            case imageURL = "image_url"
        }
    }

    // Map backend → app-facing model (with defaults for missing fields)
    private static func mapToAppModel(_ b: BackendPayload, fallbackTitle: String) -> DrugPayload {
        let mappedFood: String? = {
            switch b.food_rule ?? "none" {
            case "after_food": return "afterFood"
            case "before_food": return "beforeFood"
            case "none": return "none"
            default: return nil
            }
        }()
        return DrugPayload(
            title: (b.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
            strengths: b.strengths ?? [],
            dosageForms: [],
            foodRule: mappedFood,
            minIntervalHours: b.min_interval_hours,
            ingredients: [],
            indications: b.what_for ?? [],
            howToTake: b.how_to_take ?? [],
            commonSideEffects: b.common_side_effects ?? [],
            importantWarnings: [],
            interactionsToAvoid: b.interactions_to_avoid ?? [],
            references: nil,
            kbKey: nil
        )
    }

    /// Build DrugPayload from openFDA MedDetails + strengths (fallback when backend fails)
    private static func payloadFromOpenFDA(medName: String, details: MedDetails, strengths: [String]) -> DrugPayload {
        func toBullets(_ s: String) -> [String] {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return [] }
            let paras = t.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if paras.isEmpty { return [t] }
            return paras
        }
        return DrugPayload(
            title: details.title.isEmpty ? medName : details.title,
            strengths: strengths.isEmpty ? (details.dosage.isEmpty ? [] : [details.dosage]) : strengths,
            dosageForms: [],
            foodRule: nil,
            minIntervalHours: nil,
            ingredients: details.ingredients,
            indications: toBullets(details.uses),
            howToTake: toBullets(details.dosage),
            commonSideEffects: toBullets(details.sideEffects),
            importantWarnings: toBullets(details.warnings),
            interactionsToAvoid: toBullets(details.interactions),
            references: nil,
            kbKey: nil
        )
    }

    // MARK: - Public API

    // NAME → details (backend owns AI lookup + fallback)
    static func fetchDetails(name: String) async throws -> DrugPayload {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "DrugInfo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty medication name"])
        }

        let backend: BackendPayload = try await BackendClient.shared.request(
            "/drug-intel",
            method: .post,
            body: DrugIntelRequestBody(name: trimmed, imageURL: nil)
        )
        return mapToAppModel(backend, fallbackTitle: trimmed)
    }

    // NAME → strength options (reuse the same call)
    static func fetchDosageOptions(name: String) async throws -> [String] {
        let payload = try await fetchDetails(name: name)
        return payload.strengths
    }

    // IMAGE → details (send image_url to your Cloud Function)
    static func analyzeImage(url: URL) async throws -> DrugPayload {
        let backend: BackendPayload = try await BackendClient.shared.request(
            "/drug-intel",
            method: .post,
            body: DrugIntelRequestBody(name: nil, imageURL: url.absoluteString)
        )
        return mapToAppModel(backend, fallbackTitle: "Medication")
    }
}
