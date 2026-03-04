import Foundation
import Vapor

func analysisProviderEnabled(_ key: String, defaultEnabled: Bool = false) -> Bool {
    guard let raw = Environment.get(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return defaultEnabled
    }
    switch raw.lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off":
        return false
    default:
        return defaultEnabled
    }
}

func analysisTrimmed(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

func analysisRequestSourceText(for request: AnalysisRequest) -> String? {
    let base = [request.file_id, request.text ?? ""]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !base.isEmpty else {
        return nil
    }
    let maxCharacters = max(
        1000,
        Int(Environment.get("ORCHIVISTE_ANALYSE_APPLE_TEXT_MAX_CHARS") ?? "12000") ?? 12000
    )
    return String(base.prefix(maxCharacters))
}

func analysisEstimatedPages(for text: String?) -> Int {
    guard let text, !text.isEmpty else {
        return 1
    }
    let byFormFeed = text.components(separatedBy: "\u{0C}").count
    if byFormFeed > 1 {
        return max(1, min(500, byFormFeed))
    }
    return max(1, Int(ceil(Double(text.split(whereSeparator: \.isNewline).count) / 45.0)))
}

func analysisCanonicalTypeDocument(from raw: String?) -> String {
    let normalized = raw?
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if normalized.contains("facture") || normalized.contains("invoice") {
        return "Facture"
    }
    if normalized.contains("resolution") || normalized.contains("résolution") {
        return "Resolution"
    }
    if normalized.contains("proces-verbal") || normalized.contains("procès-verbal") || normalized == "pv" {
        return "ProcesVerbal"
    }
    if normalized.contains("permis") {
        return "Permis"
    }
    if normalized.contains("avis de motion") {
        return "AvisMotion"
    }
    if normalized.contains("depot") || normalized.contains("dépôt") {
        return "Depot"
    }
    if normalized.contains("entente")
        || normalized.contains("contrat")
        || normalized.contains("convention")
        || normalized.contains("bail")
        || normalized.contains("protocole")
        || normalized.contains("avenant") {
        return "Entente"
    }
    return raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? (raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Autre")
        : "Autre"
}

func analysisClassCode(for typeDoc: String) -> String? {
    switch typeDoc {
    case "Facture":
        return "FIN-001"
    case "Resolution":
        return "ADM-RES"
    case "ProcesVerbal":
        return "ADM-PV"
    case "Permis":
        return "URB-PER"
    case "Entente":
        return "ADM-ENT"
    case "AvisMotion":
        return "ADM-AM"
    case "Depot":
        return "ADM-DEP"
    default:
        return nil
    }
}

func analysisPresetID(for typeDoc: String) -> String? {
    switch typeDoc {
    case "Facture":
        return "preset_facture"
    case "Resolution":
        return "preset_resolution"
    case "ProcesVerbal":
        return "preset_pv"
    default:
        return "preset_default"
    }
}

func analysisDefaultSubjects(for typeDoc: String) -> [String] {
    switch typeDoc {
    case "Facture":
        return ["Finance", "Achat"]
    case "Resolution":
        return ["Decision", "Gouvernance"]
    case "ProcesVerbal":
        return ["Seance", "Comite"]
    case "Permis":
        return ["Urbanisme"]
    case "Entente":
        return ["Entente", "Partenariat"]
    case "AvisMotion":
        return ["Reglement", "Gouvernance"]
    case "Depot":
        return ["Depot", "Conformite"]
    default:
        return ["General"]
    }
}

func analysisHashedTextFeatureVector(text: String, dimension: Int) -> [Double] {
    let safeDimension = max(8, dimension)
    let tokens = analysisFeatureTokens(from: text)
    guard !tokens.isEmpty else {
        return Array(repeating: 0, count: safeDimension)
    }

    var vector = Array(repeating: 0.0, count: safeDimension)
    for token in tokens {
        let bucket = Int(analysisStableHash64(token) % UInt64(safeDimension))
        vector[bucket] += 1.0
    }

    let total = vector.reduce(0.0, +)
    guard total > 0 else {
        return vector
    }
    return vector.map { $0 / total }
}

func analysisLoadCoreMLLabelList(labelMapPath: String?, labelsCSV: String?) -> [String]? {
    if let labelsCSV {
        let labels = labelsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !labels.isEmpty {
            return labels
        }
    }

    guard let labelMapPath,
          !labelMapPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }

    let url = URL(fileURLWithPath: labelMapPath)
    guard let data = try? Data(contentsOf: url) else {
        return nil
    }

    if let labels = try? JSONDecoder().decode([String].self, from: data), !labels.isEmpty {
        return labels
    }

    if let keyed = try? JSONDecoder().decode([String: String].self, from: data), !keyed.isEmpty {
        return keyed
            .compactMap { key, value -> (Int, String)? in
                guard let index = Int(key) else { return nil }
                return (index, value)
            }
            .sorted(by: { $0.0 < $1.0 })
            .map(\.1)
    }

    return nil
}

func analysisTopSemanticTokens(text: String, limit: Int = 8) -> [String] {
    let counts = analysisFeatureTokens(from: text).reduce(into: [String: Int]()) { partial, token in
        partial[token, default: 0] += 1
    }
    return counts
        .sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
        .prefix(max(1, limit))
        .map(\.key)
}

func analysisTokenSimilarity(lhs: String, rhs: String) -> Double {
    let lhsTokens = Set(analysisFeatureTokens(from: lhs))
    let rhsTokens = Set(analysisFeatureTokens(from: rhs))
    guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
        return 0
    }
    let intersection = lhsTokens.intersection(rhsTokens).count
    let scale = sqrt(Double(lhsTokens.count * rhsTokens.count))
    guard scale > 0 else {
        return 0
    }
    return Double(intersection) / scale
}

private func analysisFeatureTokens(from text: String) -> [String] {
    let normalized = text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    let stopWords: Set<String> = [
        "avec", "dans", "pour", "sans", "dans", "par", "sur", "aux", "des", "les",
        "une", "que", "qui", "est", "sont", "dont", "ceci", "cela", "ville", "amos",
        "conseil", "municipal", "document", "fichier", "type", "objet", "resume"
    ]
    return normalized
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { token in
            token.count >= 3 && !stopWords.contains(token)
        }
}

private func analysisStableHash64(_ text: String) -> UInt64 {
    let fnvOffsetBasis: UInt64 = 1469598103934665603
    let fnvPrime: UInt64 = 1099511628211

    var hash = fnvOffsetBasis
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* fnvPrime
    }
    return hash
}
