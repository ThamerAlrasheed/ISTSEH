import Foundation

// MARK: - Public model (UNCHANGED)

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

// MARK: - Service (same name / same public methods)

enum OpenFDAService {
    // openFDA (content)
    private static let labelBase = "https://api.fda.gov/drug/label.json"
    private static let ndcBase   = "https://api.fda.gov/drug/ndc.json"

    // DailyMed (setid lookup only; SPL is XML)
    private static let dailymedBase = "https://dailymed.nlm.nih.gov/dailymed/services/v2"

    // RxNorm (name normalization)
    private static let rxnormBase = "https://rxnav.nlm.nih.gov/REST"

    // Tiny in-memory caches to keep things snappy
    private static var rxcuiCache: [String:String] = [:]      // query.lowercased() -> rxcui
    private static var setIdCache: [String:String] = [:]      // rxcui -> setid
    private static var detailsCache: [String:MedDetails] = [:]// name.lowercased() -> details

    // MARK: Public: details (call sites UNCHANGED)
    static func fetchDetails(forName name: String) async throws -> MedDetails? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let key = trimmed.lowercased()
        if let cached = detailsCache[key] { return cached }

        // Best-effort RxNorm→DailyMed prefetch in the background (do NOT block UI)
        Task.detached { await prefetchDailyMedKeying(by: trimmed) }

        // Content FIRST: openFDA brand → generic → loose text, with short timeouts
        if let doc = try await queryLabel(field: "openfda.brand_name", value: trimmed, timeout: 4) {
            let md = mapOpenFDA(doc, displayName: trimmed); detailsCache[key] = md; return md
        }
        if let doc = try await queryLabel(field: "openfda.generic_name", value: trimmed, timeout: 4) {
            let md = mapOpenFDA(doc, displayName: trimmed); detailsCache[key] = md; return md
        }
        if let doc = try await queryLabelContains(value: trimmed, timeout: 4) {
            let md = mapOpenFDA(doc, displayName: trimmed); detailsCache[key] = md; return md
        }

        // Last resort — return a shell so the UI never hangs
        let md = MedDetails(
            title: normalizedDisplayName(from: trimmed),
            uses: "", dosage: "", interactions: "", warnings: "", sideEffects: "", ingredients: []
        )
        detailsCache[key] = md
        return md
    }

    // MARK: Public: strengths (signature UNCHANGED)
    static func fetchDosageOptions(forName name: String) async throws -> [String] {
        if let strengths = try await queryNDC(field: "brand_name", value: name), !strengths.isEmpty {
            return strengths.sorted(by: strengthSort)
        }
        if let strengths = try await queryNDC(field: "generic_name", value: name), !strengths.isEmpty {
            return strengths.sorted(by: strengthSort)
        }
        return []
    }
}

// MARK: - Background prefetch (non-blocking)

private extension OpenFDAService {
    static func prefetchDailyMedKeying(by name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            if let rxcui = try await rxnormApproximateCUI(for: trimmed, timeout: 3) {
                if setIdCache[rxcui] == nil,
                   let setid = try await dailymedPrimarySetID(for: rxcui, timeout: 3) {
                    setIdCache[rxcui] = setid
                    debugLog("DailyMed setid for \(trimmed): \(setid)")
                }
            }
        } catch {
            debugLog("Prefetch skipped for \(trimmed): \(error.localizedDescription)")
        }
    }
}

// MARK: - DailyMed (correct endpoint for setid)

private extension OpenFDAService {
    /// Correct: /spls.json?rxcui=... (NOT a path segment)
    static func dailymedPrimarySetID(for rxcui: String, timeout: TimeInterval) async throws -> String? {
        let url = URL(string: "\(dailymedBase)/spls.json?rxcui=\(rxcui)&pagesize=1")!
        let data = try await fetchData(url: url, timeout: timeout)
        let decoded: DMSetList = try JSONDecoder().decode(DMSetList.self, from: data)
        return decoded.data.first?.setid
    }
}

// MARK: - RxNorm

private extension OpenFDAService {
    static func rxnormApproximateCUI(for query: String, timeout: TimeInterval) async throws -> String? {
        let key = query.lowercased()
        if let cached = rxcuiCache[key] { return cached }

        let term = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "\(rxnormBase)/approximateTerm.json?term=\(term)&maxEntries=1&option=1")!
        let data = try await fetchData(url: url, timeout: timeout)
        let decoded: RxApprox = try JSONDecoder().decode(RxApprox.self, from: data)
        let rxcui = decoded.approximateGroup?.candidate?.first?.rxcui
        if let r = rxcui { rxcuiCache[key] = r }
        return rxcui
    }

    static func normalizedDisplayName(from name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return name }
        // Soft title-casing for SHOUTY CAPS
        let tokens = t.split(separator: " ")
        return tokens.map { w in
            let s = String(w)
            if s == s.uppercased(), s.count > 2 { return s.prefix(1) + s.dropFirst().lowercased() }
            return s
        }.joined(separator: " ")
    }
}

// MARK: - openFDA label (content)

private extension OpenFDAService {
    static func queryLabel(field: String, value: String, timeout: TimeInterval) async throws -> LabelDoc? {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value

        // Try exact match first
        let exact = URL(string: "\(labelBase)?search=\(field):\"\(encoded)\"&limit=1")!
        if let doc = try? await fetchLabelDoc(url: exact, timeout: timeout) { return doc }

        // Fallback: contains
        let like = URL(string: "\(labelBase)?search=\(field):\(encoded)&limit=1")!
        return try await fetchLabelDoc(url: like, timeout: timeout)
    }

    static func queryLabelContains(value: String, timeout: TimeInterval) async throws -> LabelDoc? {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        let url = URL(string: "\(labelBase)?search=description:\(encoded)&limit=1")!
        return try await fetchLabelDoc(url: url, timeout: timeout)
    }

    static func fetchLabelDoc(url: URL, timeout: TimeInterval) async throws -> LabelDoc? {
        let data = try await fetchData(url: url, timeout: timeout)
        let decoded: LabelResponse = try JSONDecoder().decode(LabelResponse.self, from: data)
        return decoded.results?.first
    }

    static func mapOpenFDA(_ doc: LabelDoc, displayName: String) -> MedDetails {
        let uses   = cleanLabelText(join(doc.indications_and_usage))
        let dose   = cleanLabelText(join(doc.dosage_and_administration))
        let interact = cleanLabelText([join(doc.drug_interactions), join(doc.patient_information), join(doc.information_for_patients)]
            .filter { !$0.isEmpty }.joined(separator: "\n\n"))
        let warn   = cleanLabelText([join(doc.warnings), join(doc.warnings_and_cautions), join(doc.contraindications)]
            .filter { !$0.isEmpty }.joined(separator: "\n\n"))
        let se     = cleanLabelText(join(doc.adverse_reactions))
        let ingr   = (doc.openfda?.substance_name ?? []) + (doc.openfda?.pharm_class_pe ?? []) + (doc.openfda?.pharm_class_epc ?? [])

        // Prefer a title that matches what the user typed
        let fallback = normalizedDisplayName(from: displayName)
        let brand = doc.openfda?.brand_name?.first
        let generic = doc.openfda?.generic_name?.first
        let chosen: String
        if let b = brand, b.range(of: displayName, options: .caseInsensitive) != nil {
            chosen = b
        } else if let g = generic, g.range(of: displayName, options: .caseInsensitive) != nil {
            chosen = g
        } else {
            chosen = brand ?? generic ?? fallback
        }

        return MedDetails(
            title: normalizedDisplayName(from: chosen),
            uses: uses, dosage: dose, interactions: interact, warnings: warn, sideEffects: se,
            ingredients: uniq(ingr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        )
    }

    static func join(_ arr: [String]?) -> String {
        (arr ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

// MARK: - NDC strengths (UNCHANGED signature)

private extension OpenFDAService {
    static func queryNDC(field: String, value: String) async throws -> [String]? {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        let url = URL(string: "\(ndcBase)?search=\(field):\"\(encoded)\"&limit=25")!
        let data = try await fetchData(url: url, timeout: 6)
        let decoded: NDCResponse = try JSONDecoder().decode(NDCResponse.self, from: data)

        var strengths: [String] = []
        for p in decoded.results ?? [] {
            for a in p.active_ingredients ?? [] {
                if let s = a.strength { strengths.append(cleanStrength(s)) }
            }
        }
        return Array(uniq(strengths)).sorted(by: strengthSort)
    }

    static func cleanStrength(_ s: String) -> String {
        let parts = s.split(separator: " ")
        if parts.count >= 2 { return "\(parts[0]) \(parts[1])" }
        return s
    }

    static func strengthSort(_ a: String, _ b: String) -> Bool {
        func parse(_ s: String) -> (Double, String)? {
            let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let v = Double(parts[0]) else { return nil }
            return (v, parts[1].lowercased())
        }
        if let pa = parse(a), let pb = parse(b), pa.1 == pb.1 { return pa.0 < pb.0 }
        return a.localizedStandardCompare(b) == .orderedAscending
    }
}

// MARK: - Networking helper (short timeouts)

private extension OpenFDAService {
    static func fetchData(url: URL, timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}

// MARK: - Decoding structs

// DailyMed list (for setid lookup)
private struct DMSetList: Decodable {
    struct Item: Decodable {
        let setid: String?
        let spl_version: String?
        let title: String?
        let published_date: String?
    }
    let metadata: DMMetadata?
    let data: [Item]
}
private struct DMMetadata: Decodable {
    let total_elements: String?
    let elements_per_page: String?
    let total_pages: String?
    let current_page: String?
}

// openFDA label (subset)
private struct LabelResponse: Decodable { let results: [LabelDoc]? }

private struct LabelDoc: Decodable {
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
}

private struct OpenFDAFields: Decodable {
    let brand_name: [String]?
    let generic_name: [String]?
    let substance_name: [String]?
    let pharm_class_epc: [String]?
    let pharm_class_pe: [String]?
}

// NDC products (subset)
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

// RxNorm approximateTerm response
private struct RxApprox: Decodable {
    struct ApproxGroup: Decodable {
        struct Candidate: Decodable { let rxcui: String? }
        let candidate: [Candidate]?
    }
    let approximateGroup: ApproxGroup?
}

// MARK: - Small helpers

private func cleanLabelText(_ raw: String) -> String {
    // Normalize common bullet characters and excess whitespace.
    var s = raw.replacingOccurrences(of: "\r", with: "\n")
    s = s.replacingOccurrences(of: "•", with: "\n• ")
    s = s.replacingOccurrences(of: " · ", with: " ")
    // compress multiple newlines
    while s.contains("\n\n\n") { s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
    // trim spaces per line
    s = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func uniq<T: Hashable>(_ arr: [T]) -> [T] {
    var seen = Set<T>(); var out: [T] = []
    for x in arr { if !seen.contains(x) { out.append(x); seen.insert(x) } }
    return out
}

private func debugLog(_ s: String) {
    #if DEBUG
    print("[OpenFDAService] \(s)")
    #endif
}
