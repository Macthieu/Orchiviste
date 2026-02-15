import Foundation
import Vapor

struct LocalHeuristicsProvider: AnalysisProvider {
    let name = "LocalHeuristics"
    let weight: Double = 1.0

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        let text = normalizedText(request)
        let fileId = request.file_id.lowercased()
        let merged = "\(fileId) \(text)"

        let factureScore = score(
            in: merged,
            tokens: ["facture", "invoice", "montant", "tps", "tvq", "fournisseur"]
        )
        let resolutionScore = score(
            in: merged,
            tokens: ["resolution", "résolution", "attendu que", "proposé", "adopté"]
        )
        let pvScore = score(
            in: merged,
            tokens: ["proces-verbal", "procès-verbal", "séance", "comite", "comité", "ordre du jour"]
        )

        let selected: (type: String, classCode: String, baseScore: Double, sujets: [String], preset: String)
        if factureScore >= resolutionScore && factureScore >= pvScore && factureScore > 0 {
            selected = ("Facture", "FIN-001", factureScore, ["Finance", "Achat"], "preset_facture")
        } else if resolutionScore >= pvScore && resolutionScore > 0 {
            selected = ("Resolution", "ADM-RES", resolutionScore, ["Decision", "Gouvernance"], "preset_resolution")
        } else if pvScore > 0 {
            selected = ("ProcesVerbal", "ADM-PV", pvScore, ["Seance", "Comite"], "preset_pv")
        } else {
            selected = ("Autre", "GEN-000", 0.25, ["General"], "preset_default")
        }

        let hasSignature = containsAny(in: merged, tokens: ["signature", "signé", "signed"])
        let pages = estimatedPages(from: request.text)
        let champs = extractFields(from: request.text ?? "")
        let confidence = min(0.95, max(0.2, 0.35 + selected.baseScore))

        var matchedRules = [String]()
        if factureScore > 0 { matchedRules.append("rule_facture_tokens") }
        if resolutionScore > 0 { matchedRules.append("rule_resolution_tokens") }
        if pvScore > 0 { matchedRules.append("rule_pv_tokens") }
        if hasSignature { matchedRules.append("rule_signature_detected") }
        if matchedRules.isEmpty { matchedRules.append("rule_fallback_autre") }

        logger.debug("Analyse heuristique locale terminée.", metadata: [
            "file_id": .string(request.file_id),
            "type_doc": .string(selected.type),
            "confidence": .string("\(confidence)")
        ])

        return ProviderCandidate(
            provider: name,
            typeDoc: selected.type,
            sujets: selected.sujets,
            hasSignature: hasSignature,
            pages: pages,
            champs: champs,
            confidence: confidence,
            suggestedPreset: request.preset_id ?? selected.preset,
            suggestedClassCode: selected.classCode,
            matchedRules: matchedRules,
            topNodes: [selected.classCode]
        )
    }

    private func normalizedText(_ request: AnalysisRequest) -> String {
        (request.text ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func score(in text: String, tokens: [String]) -> Double {
        guard !tokens.isEmpty else { return 0 }
        let hits = tokens.reduce(into: 0) { partial, token in
            if text.contains(token) {
                partial += 1
            }
        }
        return Double(hits) / Double(tokens.count)
    }

    private func containsAny(in text: String, tokens: [String]) -> Bool {
        tokens.contains { text.contains($0) }
    }

    private func estimatedPages(from text: String?) -> Int {
        guard let text, !text.isEmpty else { return 1 }
        let byFormFeed = text.components(separatedBy: "\u{0C}").count
        if byFormFeed > 1 {
            return max(1, min(500, byFormFeed))
        }
        let lineCount = text.split(whereSeparator: \.isNewline).count
        return max(1, min(500, Int(ceil(Double(lineCount) / 45.0))))
    }

    private func extractFields(from text: String) -> [String: String] {
        let lower = text.lowercased()
        var fields: [String: String] = [:]

        if let number = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:pv|res|r|fac|facture)[-\s]?\d{2,4}(?:[-/]\d+)?\b"#
        ) {
            fields["numero"] = number
        }
        if let date = firstMatch(
            in: text,
            pattern: #"\b(?:20\d{2}[-/]\d{2}[-/]\d{2}|\d{4}-\d{2}-\d{2})\b"#
        ) {
            fields["date"] = date
        }

        if let committeeName = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:comite|comité|committee)\s*[:\-]?\s*([^\n\r,;.]+)"#
        ) {
            fields["comite"] = cleanupCommittee(committeeName)
        } else if lower.contains("conseil") {
            fields["comite"] = "Conseil"
        }

        return fields
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        let targetRange: NSRange
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
            targetRange = match.range(at: 1)
        } else {
            targetRange = match.range
        }
        guard let swiftRange = Range(targetRange, in: text) else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanupCommittee(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
