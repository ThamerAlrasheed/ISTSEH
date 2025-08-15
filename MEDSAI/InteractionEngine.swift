import Foundation

struct InteractionRules: Decodable {
    struct ClassRule: Decodable {
        let members: [String]
        let separateFrom: [String: Double]?
        let avoidWith: [String]?
        let notes: [String]?
    }
    let classes: [String: ClassRule]
    let aliases: [String: [String]]?
}

struct InteractionConflict: Identifiable {
    enum Kind { case avoid, separate(hours: Double) }
    let id = UUID()
    let medA: String
    let medB: String
    let kind: Kind
    let explanation: String
}

enum InteractionEngine {
    static var rules: InteractionRules = {
        guard let url = Bundle.main.url(forResource: "InteractionRules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(InteractionRules.self, from: data) else {
            return InteractionRules(classes: [:], aliases: [:])
        }
        return decoded
    }()

    static func checkConflicts(meds: [(name: String, ingredients: [String])]) -> [InteractionConflict] {
        var conflicts: [InteractionConflict] = []
        let list = meds.map { ($0.name.lowercased(), $0.ingredients.map{$0.lowercased()}) }
        for i in 0..<list.count {
            for j in (i+1)..<list.count {
                let a = list[i], b = list[j]
                let aClasses = classesContaining(a.1 + [a.0])
                let bClasses = classesContaining(b.1 + [b.0])
                conflicts += conflictsBetween(aName: a.0, aClasses: aClasses, bName: b.0, bIngredients: b.1)
                conflicts += conflictsBetween(aName: b.0, aClasses: bClasses, bName: a.0, bIngredients: a.1)
            }
        }
        return dedupe(conflicts)
    }

    private static func conflictsBetween(aName: String, aClasses: [String], bName: String, bIngredients: [String]) -> [InteractionConflict] {
        var out: [InteractionConflict] = []
        for cls in aClasses {
            guard let rule = rules.classes[cls] else { continue }
            for avoid in rule.avoidWith ?? [] {
                if matches(nameOrClass: avoid, against: bName, ingredients: bIngredients) {
                    out.append(.init(medA: aName, medB: bName, kind: .avoid,
                                     explanation: "Avoid combining \(aName) with \(bName)"))
                }
            }
            for (other, hours) in rule.separateFrom ?? [:] {
                if matches(nameOrClass: other, against: bName, ingredients: bIngredients) {
                    out.append(.init(medA: aName, medB: bName, kind: .separate(hours: hours),
                                     explanation: "Keep \(aName) and \(bName) \(hours)h apart"))
                }
            }
        }
        return out
    }

    private static func classesContaining(_ names: [String]) -> [String] {
        let set = Set(names.map { $0.lowercased() })
        return rules.classes.compactMap { key, rule in
            rule.members.contains(where: { set.contains($0.lowercased()) }) ? key : nil
        }
    }

    private static func matches(nameOrClass: String, against medName: String, ingredients: [String]) -> Bool {
        let t = nameOrClass.lowercased()
        let all = [medName.lowercased()] + ingredients.map { $0.lowercased() }
        if all.contains(where: { $0 == t }) { return true }
        if let al = rules.aliases?[t], !al.isEmpty, all.contains(where: { al.contains($0) }) { return true }
        if let classRule = rules.classes[t] {
            return all.contains(where: { classRule.members.map{$0.lowercased()}.contains($0) })
        }
        return false
    }

    private static func dedupe(_ arr: [InteractionConflict]) -> [InteractionConflict] {
        var seen = Set<String>(), out: [InteractionConflict] = []
        for c in arr {
            let key: String = switch c.kind {
                case .avoid: "A:\(c.medA)-B:\(c.medB)-avoid"
                case .separate(let h): "A:\(c.medA)-B:\(c.medB)-sep:\(h)"
            }
            if seen.insert(key).inserted { out.append(c) }
        }
        return out
    }
}
