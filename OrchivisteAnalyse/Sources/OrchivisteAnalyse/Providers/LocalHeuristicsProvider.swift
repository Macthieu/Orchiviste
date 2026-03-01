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

        let hasSignature = containsAny(in: merged, tokens: ["signature", "signe", "signed"])
        let pages = estimatedPages(from: request.text)
        let extracted = extractFields(from: "\(request.file_id)\n\(request.text ?? "")")
        let extractedFields = extracted.fields
        let idp = IDPSemanticPipeline.run(
            request: request,
            typeDoc: selected.type,
            baseFields: extractedFields
        )
        let champs = mergeFields(primary: extractedFields, secondary: idp.semanticFields)
        let fieldSources = extracted.fieldSources.merging(idp.fieldSources) { current, _ in current }
        let confidence = adjustedConfidence(
            baseScore: selected.baseScore,
            completeness: idp.completenessScore,
            validationFlags: idp.validationFlags
        )
        let inferredSujets = inferSubjects(request: request)
        let sujets = mergeSubjects(defaultSujets: selected.sujets, inferred: inferredSujets, typeDoc: selected.type)

        var matchedRules = [String]()
        if factureScore > 0 { matchedRules.append("rule_facture_tokens") }
        if resolutionScore > 0 { matchedRules.append("rule_resolution_tokens") }
        if pvScore > 0 { matchedRules.append("rule_pv_tokens") }
        if hasSignature { matchedRules.append("rule_signature_detected") }
        if !idp.relevantPages.isEmpty { matchedRules.append("rule_idp_relevant_pages") }
        if idp.hasTableLayout { matchedRules.append("rule_idp_layout_table_detected") }
        if idp.clauseAttenduQueCount > 0 { matchedRules.append("rule_idp_clause_attendu_que") }
        if idp.clauseResoluCount > 0 { matchedRules.append("rule_idp_clause_resolu") }
        if idp.captureStrategy == "ocr_semantic_assisted" {
            matchedRules.append("rule_idp_capture_ocr_semantic")
        }
        if idp.segmentation.unitCount > 1 {
            matchedRules.append("rule_idp_multi_document_units")
        }
        if idp.validationFlags.isEmpty {
            matchedRules.append("rule_idp_validation_complete")
        } else {
            matchedRules.append("rule_idp_validation_flags_present")
        }
        if idp.review.needsReview {
            matchedRules.append("rule_idp_review_required")
        }
        if matchedRules.isEmpty { matchedRules.append("rule_fallback_autre") }

        let capture = AnalysisCapture(
            strategy: idp.captureStrategy,
            unit_count: idp.segmentation.unitCount,
            section_titles: idp.segmentation.sectionTitles,
            boundary_markers: idp.segmentation.boundaryMarkers,
            field_sources: fieldSources,
            warnings: idp.warnings
        )
        let review = AnalysisReview(
            needs_review: idp.review.needsReview,
            reasons: idp.review.reasons,
            missing_fields: idp.review.missingFields,
            ambiguous_fields: idp.review.ambiguousFields
        )

        logger.debug("Analyse heuristique locale terminée.", metadata: [
            "file_id": .string(request.file_id),
            "type_doc": .string(selected.type),
            "confidence": .string("\(confidence)")
        ])

        return ProviderCandidate(
            provider: name,
            typeDoc: selected.type,
            sujets: sujets,
            hasSignature: hasSignature,
            pages: pages,
            champs: champs,
            confidence: confidence,
            suggestedPreset: request.preset_id ?? selected.preset,
            suggestedClassCode: selected.classCode,
            matchedRules: matchedRules,
            topNodes: [selected.classCode] + Array(idp.titleHints.prefix(2)),
            capture: capture,
            review: review
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

    private func extractFields(
        from text: String
    ) -> (fields: [String: String], fieldSources: [String: AnalysisFieldSource]) {
        let lower = text.lowercased()
        var fields: [String: String] = [:]
        var fieldSources: [String: AnalysisFieldSource] = [:]

        if let number = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:pv|res|r|fac|facture)[-\s]?\d{2,4}(?:[-/]\d+)?\b"#
        ) {
            fields["numero"] = number
            fieldSources["numero"] = AnalysisFieldSource(
                source: "regex_primary_document_number",
                confidence: 0.77,
                evidence: number
            )
        }
        if let date = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:20\d{2}[-/]\d{2}[-/]\d{2}|\d{4}-\d{2}-\d{2}|[0-3]?\d\s+(?:janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre)\s+20\d{2})\b"#
        ) {
            fields["date"] = date
            fieldSources["date"] = AnalysisFieldSource(
                source: "regex_primary_date",
                confidence: 0.75,
                evidence: date
            )
        }

        if let committeeName = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:comite|comité|committee)\s*[:\-]?\s*([^\n\r,;.]+)"#
        ) {
            fields["comite"] = cleanupCommittee(committeeName)
            fieldSources["comite"] = AnalysisFieldSource(
                source: "regex_committee_heading",
                confidence: 0.72,
                evidence: committeeName
            )
        } else if lower.contains("conseil") {
            fields["comite"] = "Conseil"
            fieldSources["comite"] = AnalysisFieldSource(
                source: "keyword_conseil",
                confidence: 0.55,
                evidence: "Conseil"
            )
        }

        return (fields, fieldSources)
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

    private func inferSubjects(request: AnalysisRequest) -> [String] {
        let source = "\(request.file_id) \(request.text ?? "")"
        let cleaned = source
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .lowercased()
        let stopwords: Set<String> = [
            "pdf", "file", "name", "tags", "data", "job", "uuid", "comite", "comitee",
            "session", "general", "autre", "archives", "analyse", "preview", "texte",
            "dossier", "fichier", "local", "sharepoint", "projet", "demande", "adoption"
        ]
        var sujets: [String] = []
        for token in cleaned.split(separator: " ").map(String.init) {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 4 { continue }
            if stopwords.contains(trimmed) { continue }
            if trimmed.allSatisfy({ $0.isNumber }) { continue }
            let normalized = trimmed.capitalized
            if sujets.contains(normalized) { continue }
            sujets.append(normalized)
            if sujets.count == 2 { break }
        }
        return sujets
    }

    private func mergeSubjects(defaultSujets: [String], inferred: [String], typeDoc: String) -> [String] {
        if inferred.isEmpty {
            return defaultSujets
        }
        if typeDoc == "Autre" {
            return inferred
        }
        var merged = defaultSujets
        for sujet in inferred {
            if merged.count >= 2 { break }
            if !merged.contains(sujet) {
                merged.append(sujet)
            }
        }
        return merged
    }

    private func mergeFields(
        primary: [String: String],
        secondary: [String: String]
    ) -> [String: String] {
        primary.merging(secondary) { current, incoming in
            let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCurrent.isEmpty {
                return incoming
            }
            return current
        }
    }

    private func adjustedConfidence(
        baseScore: Double,
        completeness: Double,
        validationFlags: [String]
    ) -> Double {
        let base = 0.35 + baseScore
        let completenessBoost = (completeness - 0.5) * 0.25
        let validationPenalty = Double(validationFlags.count) * 0.06
        let adjusted = base + completenessBoost - validationPenalty
        return min(0.95, max(0.2, adjusted))
    }
}
