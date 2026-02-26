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

    // ⚠️ Your deployed endpoint
    private static let endpoint = URL(string: "https://us-central1-istseh.cloudfunctions.net/drugIntel")!

    // Common POST call
    private static func postJSON(body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20

        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DrugInfo", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "Server error \(status). \(snippet)"])
        }
        return data
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

    // NAME → details (Cloud Function first, then openFDA fallback)
    static func fetchDetails(name: String) async throws -> DrugPayload {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "DrugInfo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty medication name"])
        }

        // 1) Try Cloud Function (GPT) first
        do {
            let data = try await postJSON(body: ["name": trimmed])
            let backend = try JSONDecoder().decode(BackendPayload.self, from: data)
            return mapToAppModel(backend, fallbackTitle: trimmed)
        } catch {
            // 2) Fallback: openFDA label + NDC strengths so user still gets data
            if let details = try? await OpenFDAService.fetchDetails(forName: trimmed) {
                let strengths = (try? await OpenFDAService.fetchDosageOptions(forName: trimmed)) ?? []
                return payloadFromOpenFDA(medName: trimmed, details: details, strengths: strengths)
            }
            throw error
        }
    }

    // NAME → strength options (reuse the same call)
    static func fetchDosageOptions(name: String) async throws -> [String] {
        let payload = try await fetchDetails(name: name)
        return payload.strengths
    }

    // IMAGE → details (send image_url to your Cloud Function)
    static func analyzeImage(url: URL) async throws -> DrugPayload {
        let data = try await postJSON(body: ["image_url": url.absoluteString])
        let backend = try JSONDecoder().decode(BackendPayload.self, from: data)
        return mapToAppModel(backend, fallbackTitle: "Medication")
    }
}
