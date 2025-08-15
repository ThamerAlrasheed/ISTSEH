import Foundation

// MARK: - LABEL (existing)

struct LabelResponse: Decodable { let results: [LabelDoc]? }

struct LabelDoc: Decodable {
    let indications_and_usage: [String]?
    let dosage_and_administration: [String]?
    let contraindications: [String]?
    let warnings: [String]?
    let warnings_and_cautions: [String]?
    let adverse_reactions: [String]?
    let drug_interactions: [String]?
    let patient_information: [String]?
    let information_for_patients: [String]?
    let openfda: OpenFDAFields?
    var ingredients: [String] { openfda?.substance_name ?? [] }
}

struct OpenFDAFields: Decodable {
    let brand_name: [String]?
    let generic_name: [String]?
    let substance_name: [String]?
}

struct MedDetails {
    let title: String
    let uses: String
    let dosage: String
    let interactions: String
    let warnings: String
    let sideEffects: String
    let ingredients: [String]
}

extension MedDetails {
    var combinedText: String {
        [uses, dosage, interactions, warnings, sideEffects]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

// MARK: - NDC (NEW for strengths)

private struct NDCResponse: Decodable { let results: [NDCProduct]? }

private struct NDCProduct: Decodable {
    struct ActiveIngredient: Decodable {
        let name: String?
        let strength: String?   // e.g. "10 mg/1", "10 mg/10 mL", "500 mg/1"
    }
    let brand_name: String?
    let generic_name: String?
    let dosage_form: String?
    let route: [String]?
    let active_ingredients: [ActiveIngredient]?
}

// MARK: - Service

enum OpenFDAService {
    private static let labelBase = "https://api.fda.gov/drug/label.json"
    private static let ndcBase   = "https://api.fda.gov/drug/ndc.json"

    // Fetch label-derived details (existing)
    static func fetchDetails(forName name: String) async throws -> MedDetails? {
        if let doc = try await queryLabel(field: "openfda.brand_name", value: name) {
            return mapLabel(doc)
        }
        if let doc = try await queryLabel(field: "openfda.generic_name", value: name) {
            return mapLabel(doc)
        }
        return nil
    }

    // NEW: Fetch a curated list of marketed strengths (e.g., ["5 mg","10 mg"])
    static func fetchDosageOptions(forName name: String) async throws -> [String] {
        // Try brand name first, then generic name
        let fromBrand  = try await queryNDC(field: "brand_name", value: name)
        let fromGeneric = try await queryNDC(field: "generic_name", value: name)
        let products = (fromBrand ?? []) + (fromGeneric ?? [])

        // Collect strengths from active_ingredients.strength
        var options = Set<String>()
        for p in products {
            guard let ais = p.active_ingredients else { continue }
            for ai in ais {
                if let strength = ai.strength,
                   let normalized = normalizeStrength(strength) {
                    options.insert(normalized)
                }
            }
        }

        // Return consistently sorted (numerical if possible, then lexicographic)
        let sorted = options.sorted(by: strengthSort)
        return sorted
    }

    // MARK: - Private label helpers

    private static func queryLabel(field: String, value: String) async throws -> LabelDoc? {
        var comps = URLComponents(string: labelBase)!
        let search = "\(field):\"\(value)\""
        comps.queryItems = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = comps.url else { return nil }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoded = try JSONDecoder().decode(LabelResponse.self, from: data)
        return decoded.results?.first
    }

    private static func mapLabel(_ d: LabelDoc) -> MedDetails {
        func join(_ arr: [String]?) -> String {
            (arr ?? []).joined(separator: "\n\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = d.openfda?.brand_name?.first ?? d.openfda?.generic_name?.first ?? "Drug information"
        return MedDetails(
            title: title,
            uses: join(d.indications_and_usage),
            dosage: join(d.dosage_and_administration),
            interactions: join(d.drug_interactions),
            warnings: join(d.warnings ?? d.warnings_and_cautions),
            sideEffects: join(d.adverse_reactions),
            ingredients: d.ingredients
        )
    }

    // MARK: - Private NDC helpers

    private static func queryNDC(field: String, value: String) async throws -> [NDCProduct]? {
        var comps = URLComponents(string: ndcBase)!
        // Exact phrase search for safety; bump limit to catch all presentations
        let search = "\(field):\"\(value)\""
        comps.queryItems = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "limit", value: "50")
        ]
        guard let url = comps.url else { return nil }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoded = try JSONDecoder().decode(NDCResponse.self, from: data)
        return decoded.results
    }

    /// Normalize openFDA NDC strength strings into simple, user-friendly options.
    /// Examples:
    /// - "10 mg/1"         -> "10 mg"
    /// - "10 mg/10 mL"     -> "10 mg"
    /// - "250 mg/5 mL"     -> "250 mg"
    /// - "20 mg/2"         -> "20 mg"
    /// - "400 mg/5 ml"     -> "400 mg"
    private static func normalizeStrength(_ s: String) -> String? {
        // We only surface the numerator (first part) and unit (mg/mcg/g/mL) as a friendly dose option.
        // This intentionally avoids concentration complexity for liquids; the "Amount" picker is for unit dose strengths,
        // and liquids remain editable via manual entry if needed.
        // Patterns we accept: "<number> <unit> / <something>"
        // Fallback: if string is simple like "10 mg", keep it.

        // Strip extra spaces and lowercase
        let text = s
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Quick match for a plain amount like "10 mg"
        if let m = text.range(of: #"^\s*(\d+(?:\.\d+)?)\s*(mg|mcg|g|ml)\s*$"#, options: .regularExpression) {
            let sub = String(text[m])
            // normalize spacing and unit case
            let parts = sub.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2 { return "\(parts[0]) \(parts[1].uppercased())".replacingOccurrences(of: "ML", with: "mL") }
        }

        // Generic numerator/denominator pattern: "X unit / Y ..." -> take X unit
        // Examples: "10 mg/1", "250 mg/5 mL", "1 g/10 mL"
        let pattern = #"^\s*(\d+(?:\.\d+)?)\s*(mg|mcg|g)\s*/\s*[\d\.]+\s*[a-z]*\s*$"#
        if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let m = rx.firstMatch(in: text, options: [], range: range),
               m.numberOfRanges >= 3,
               let rNum = Range(m.range(at: 1), in: text),
               let rUnit = Range(m.range(at: 2), in: text) {
                let num = String(text[rNum])
                let unit = String(text[rUnit]).lowercased()
                let capUnit = unit == "ml" ? "mL" : unit.uppercased()
                return "\(num) \(capUnit)"
            }
        }

        // If it's something like "10 mg/10 mL" we still want "10 mg"
        if let m = text.range(of: #"^\s*(\d+(?:\.\d+)?)\s*(mg|mcg|g)\s*/"#, options: .regularExpression) {
            // Extract numerator + unit
            let sub = String(text[m])
                .replacingOccurrences(of: "/", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = sub.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                let unit = parts[1].lowercased()
                let capUnit = unit == "ml" ? "mL" : unit.uppercased()
                return "\(parts[0]) \(capUnit)"
            }
        }

        // Last resort: try to find a number + unit at start
        if let m = text.range(of: #"^\s*(\d+(?:\.\d+)?)\s*(mg|mcg|g|ml)\b"#, options: .regularExpression) {
            let sub = String(text[m]).trimmingCharacters(in: .whitespaces)
            let parts = sub.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2 {
                let unit = parts[1].lowercased()
                let capUnit = unit == "ml" ? "mL" : unit.uppercased()
                return "\(parts[0]) \(capUnit)"
            }
        }

        return nil
    }

    private static func strengthSort(_ a: String, _ b: String) -> Bool {
        // Attempt numeric-first sort (by mg/mcg/g); fallback to string compare
        func parse(_ s: String) -> (Double, String)? {
            let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let v = Double(parts[0]) else { return nil }
            return (v, parts[1].lowercased())
        }
        if let pa = parse(a), let pb = parse(b), pa.1 == pb.1 {
            return pa.0 < pb.0
        }
        return a.localizedStandardCompare(b) == .orderedAscending
    }
}
