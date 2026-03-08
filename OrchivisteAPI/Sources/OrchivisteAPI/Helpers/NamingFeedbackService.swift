import Foundation
import OrchivisteAnalyseCore
import OrchivisteSharedKit
import Vapor

struct NamingFeedbackRequest: Content {
    let job_id: String
    let naming_rule_id: String?
    let corrected_file_name: String
    let notes: String?
}

struct NamingFeedbackResponse: Content {
    let job_id: String
    let rule_id: String
    let thesaurus_id: String
    let learned_aliases: [String]
    let preserved_acronyms: [String]
}

enum NamingFeedbackService {
    static func apply(
        request: NamingFeedbackRequest,
        job: JobRecord,
        analysis: AnalysisResponse?
    ) throws -> NamingFeedbackResponse {
        let correctedFileName = sanitizeCorrectedFileName(request.corrected_file_name)
        guard FilenameGuardrails.validateCandidateStem(correctedFileName) == nil else {
            throw Abort(.badRequest, reason: "Le nom corrigé ne respecte pas les garde-fous de nommage.")
        }

        let presets = ConfigLoader.loadPresets()
        let preset = presets.first { $0.id == job.suggestedPreset }
        let catalog = ConfigLoader.loadNamingRuntimeCatalog()
        let rules = catalog.activeRuleDefinitions()
        let rule = request.naming_rule_id.flatMap { catalog.ruleRecord(id: $0, includeDrafts: true)?.definition }
            ?? selectNamingRuleForRouting(job: job, analysis: analysis, preset: preset, rules: rules)
        guard let rule else {
            throw Abort(.notFound, reason: "Aucune règle de nommage exploitable pour cette tâche.")
        }

        var thesaurus = catalog.primaryThesaurus() ?? NamingFoundationSeeds.bootstrapFallbackThesaurus()
        let engine = DeclarativeNamingRuleEngine()
        let sourceURL = URL(fileURLWithPath: job.fileURL)
        let detectionText = buildNamingDetectionText(job: job, analysis: analysis, preset: preset)
        let metadata = NamingSourceMetadata(
            fileName: sourceURL.lastPathComponent,
            fileExtension: sourceURL.pathExtension,
            originalName: sourceURL.lastPathComponent,
            hints: job.analysisChamps
        )

        var extracted = engine.extractFields(from: detectionText, rule: rule, metadata: metadata)
        for (key, value) in overlayNamingFields(job: job, analysis: analysis, sourceURL: sourceURL) {
            if key == "date" {
                extracted[key] = value
                continue
            }
            if shouldUseOverlayField(key: key, existing: extracted[key], incoming: value) {
                extracted[key] = value
            }
        }
        let normalized = engine.normalizeFields(extracted, rule: rule, thesaurus: thesaurus)
        let correctedFields = parseFields(from: correctedFileName, template: rule.template)
        let semanticMatches = semanticFeedbackMatches(
            correctedFields: correctedFields,
            sourceFields: normalized,
            analysis: analysis
        )

        var learnedAliases: [String] = []
        var learnedAliasFingerprints = Set<String>()
        let candidateFieldKeys = ["titre", "objet", "cocontractant"]
        func recordAliasIfNeeded(sourceValue: String, correctedValue: String, fieldKey: String) {
            let sourceTrimmed = sourceValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let correctedTrimmed = correctedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceTrimmed.isEmpty,
                  !correctedTrimmed.isEmpty,
                  normalizedFeedbackToken(sourceTrimmed) != normalizedFeedbackToken(correctedTrimmed) else {
                return
            }
            let fingerprint = "\(fieldKey)|\(normalizedFeedbackToken(sourceTrimmed))|\(normalizedFeedbackToken(correctedTrimmed))"
            guard !learnedAliasFingerprints.contains(fingerprint) else {
                return
            }
            thesaurus = upsertingFeedbackAlias(
                in: thesaurus,
                sourceValue: sourceTrimmed,
                correctedValue: correctedTrimmed,
                fieldKey: fieldKey
            )
            learnedAliasFingerprints.insert(fingerprint)
            learnedAliases.append("\(sourceTrimmed) -> \(correctedTrimmed)")
        }

        for key in candidateFieldKeys {
            guard let sourceValue = normalized[key],
                  let correctedValue = correctedFields[key] else {
                continue
            }
            recordAliasIfNeeded(sourceValue: sourceValue, correctedValue: correctedValue, fieldKey: key)
        }
        for match in semanticMatches where candidateFieldKeys.contains(match.field_key) {
            recordAliasIfNeeded(
                sourceValue: match.source_value,
                correctedValue: match.corrected_value,
                fieldKey: match.field_key
            )
        }

        let preservedAcronyms = extractUppercaseAcronyms(from: correctedFields["titre"] ?? correctedFields["objet"] ?? "")
        let feedbackNotes = mergedFeedbackNotes(
            baseNotes: request.notes,
            semanticMatches: semanticMatches
        )
        let updatedRule = appendFeedback(
            to: rule,
            sourceFileName: sourceURL.lastPathComponent,
            correctedFileName: correctedFileName,
            sourceFields: normalized,
            correctedFields: correctedFields,
            notes: feedbackNotes,
            preservedAcronyms: preservedAcronyms
        )

        try ConfigLoader.saveNamingRule(updatedRule)
        try ConfigLoader.saveNamingThesaurus(thesaurus)
        try ConfigLoader.namingStore().recordFeedback(
            PersistedNamingFeedback(
                feedback_id: "feedback-\(request.job_id)-\(UUID().uuidString)",
                rule_id: updatedRule.id,
                created_at: Date(),
                source: .feedback,
                feedback: NamingFeedbackExample(
                    created_at: Date(),
                    source_filename: sourceURL.lastPathComponent,
                    corrected_filename: correctedFileName,
                    source_fields: normalized,
                    corrected_fields: correctedFields.isEmpty ? nil : correctedFields,
                    notes: feedbackNotes
                )
            )
        )

        return NamingFeedbackResponse(
            job_id: request.job_id,
            rule_id: updatedRule.id,
            thesaurus_id: thesaurus.thesaurus_id,
            learned_aliases: learnedAliases,
            preserved_acronyms: preservedAcronyms
        )
    }
}

private func sanitizeCorrectedFileName(_ raw: String) -> String {
    var value = FilenameGuardrails.normalizeFrenchTypography(raw)
    value = value.replacingOccurrences(of: #"\s+\.pdf$"#, with: ".pdf", options: .regularExpression)
    if !value.lowercased().hasSuffix(".pdf") {
        value += ".pdf"
    }
    return value
}

private func parseFields(from fileName: String, template: String) -> [String: String] {
    if let strict = parseFields(from: fileName, template: template, flexibleLiterals: false), !strict.isEmpty {
        return strict
    }
    if let flexible = parseFields(from: fileName, template: template, flexibleLiterals: true), !flexible.isEmpty {
        return flexible
    }
    return [:]
}

private func parseFields(
    from fileName: String,
    template: String,
    flexibleLiterals: Bool
) -> [String: String]? {
    let placeholderRegex = try? NSRegularExpression(pattern: #"\{([^}]+)\}"#)
    let range = NSRange(template.startIndex..<template.endIndex, in: template)
    let matches = placeholderRegex?.matches(in: template, range: range) ?? []
    guard !matches.isEmpty else {
        return [:]
    }

    var pattern = "^"
    var fieldKeys: [String] = []
    var cursor = template.startIndex
    for match in matches {
        guard let fullRange = Range(match.range(at: 0), in: template),
              let keyRange = Range(match.range(at: 1), in: template) else {
            continue
        }
        let literal = String(template[cursor..<fullRange.lowerBound])
        pattern += literalPattern(literal, flexible: flexibleLiterals)
        pattern += "(.+?)"
        fieldKeys.append(String(template[keyRange]))
        cursor = fullRange.upperBound
    }
    pattern += literalPattern(String(template[cursor...]), flexible: flexibleLiterals)
    pattern += "$"

    let options: NSRegularExpression.Options = flexibleLiterals ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
          let match = regex.firstMatch(
            in: fileName,
            range: NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
          ) else {
        return nil
    }

    var fields: [String: String] = [:]
    for (index, key) in fieldKeys.enumerated() {
        let captureIndex = index + 1
        guard captureIndex < match.numberOfRanges,
              let captureRange = Range(match.range(at: captureIndex), in: fileName) else {
            continue
        }
        fields[key] = String(fileName[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return fields
}

private func literalPattern(_ literal: String, flexible: Bool) -> String {
    guard flexible else {
        return NSRegularExpression.escapedPattern(for: literal)
    }

    var pattern = ""
    var previousWasWhitespace = false
    for character in literal {
        if character.isWhitespace {
            if !previousWasWhitespace {
                pattern += #"\s+"#
                previousWasWhitespace = true
            }
            continue
        }
        previousWasWhitespace = false
        if character == "–" || character == "-" {
            pattern += #"\s*[–-]\s*"#
            continue
        }
        pattern += NSRegularExpression.escapedPattern(for: String(character))
    }
    return pattern
}

private func normalizedFeedbackToken(_ raw: String) -> String {
    raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func feedbackSimilarityScore(_ lhs: String, _ rhs: String) -> Double {
    let lhsTokens = Set(normalizedFeedbackToken(lhs).split(separator: " ").map(String.init))
    let rhsTokens = Set(normalizedFeedbackToken(rhs).split(separator: " ").map(String.init))
    guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
        return 0
    }
    let intersection = lhsTokens.intersection(rhsTokens).count
    let union = lhsTokens.union(rhsTokens).count
    guard union > 0 else {
        return 0
    }
    return Double(intersection) / Double(union)
}

private func upsertingFeedbackAlias(
    in thesaurus: NamingThesaurus,
    sourceValue: String,
    correctedValue: String,
    fieldKey: String
) -> NamingThesaurus {
    let normalizedSource = normalizedFeedbackToken(sourceValue)
    let normalizedCanonical = normalizedFeedbackToken(correctedValue)
    guard !normalizedSource.isEmpty, !normalizedCanonical.isEmpty else {
        return thesaurus
    }

    var entries = thesaurus.entries
    if let index = entries.firstIndex(where: { normalizedFeedbackToken($0.canonical) == normalizedCanonical }) {
        var entry = entries[index]
        let aliases = Array(Set(entry.aliases + [sourceValue])).sorted()
        entry = NamingThesaurusEntry(
            canonical: correctedValue,
            aliases: aliases,
            kind: entry.kind ?? "naming_feedback_\(fieldKey)",
            normalized_output: entry.normalized_output ?? correctedValue,
            preserve_terms: entry.preserve_terms,
            notes: entry.notes
        )
        entries[index] = entry
    } else {
        entries.append(
            NamingThesaurusEntry(
                canonical: correctedValue,
                aliases: [sourceValue],
                kind: "naming_feedback_\(fieldKey)",
                normalized_output: correctedValue,
                preserve_terms: nil,
                notes: ["Ajouté depuis une correction manuelle de nommage."]
            )
        )
    }

    return NamingThesaurus(
        thesaurus_id: thesaurus.thesaurus_id,
        version: thesaurus.version,
        description: thesaurus.description,
        trace: thesaurus.trace,
        entries: entries,
        stopwords: thesaurus.stopwords,
        preserve_terms: thesaurus.preserve_terms
    )
}

private func appendFeedback(
    to rule: NamingRuleDefinition,
    sourceFileName: String,
    correctedFileName: String,
    sourceFields: [String: String],
    correctedFields: [String: String],
    notes: String?,
    preservedAcronyms: [String]
) -> NamingRuleDefinition {
    let currentMetadata = rule.metadata ?? NamingRuleMetadata()
    let currentRendering = currentMetadata.rendering ?? NamingRenderingOptions()
    let mergedAcronyms = Array(
        Set((currentRendering.preserve_acronyms ?? []) + preservedAcronyms)
    ).sorted()
    let feedback = NamingFeedbackExample(
        created_at: Date(),
        source_filename: sourceFileName,
        corrected_filename: correctedFileName,
        source_fields: sourceFields.isEmpty ? nil : sourceFields,
        corrected_fields: correctedFields.isEmpty ? nil : correctedFields,
        notes: notes
    )
    let feedbackExamples = Array((currentMetadata.feedback_examples ?? []) + [feedback]).suffix(25)
    let metadata = NamingRuleMetadata(
        suggested_class_code: currentMetadata.suggested_class_code,
        canonical_output_label: currentMetadata.canonical_output_label,
        rendering: NamingRenderingOptions(
            title_source: currentRendering.title_source,
            title_case: currentRendering.title_case,
            preserve_acronyms: mergedAcronyms,
            title_max_length: currentRendering.title_max_length,
            sharepoint_safe_filename_length: currentRendering.sharepoint_safe_filename_length
        ),
        feedback_examples: Array(feedbackExamples),
        notes: currentMetadata.notes
    )

    return NamingRuleDefinition(
        id: rule.id,
        label: rule.label,
        version: rule.version,
        document_family: rule.document_family,
        template: rule.template,
        conditions: rule.conditions,
        fields: rule.fields,
        normalization: rule.normalization,
        forbidden_terms: rule.forbidden_terms,
        validations: rule.validations,
        metadata: metadata
    )
}

private func extractUppercaseAcronyms(from value: String) -> [String] {
    let regex = try? NSRegularExpression(pattern: #"\b[A-ZÀÂÇÉÈÊËÎÏÔÙÛÜ]{2,8}\b"#)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    let matches = regex?.matches(in: value, range: range) ?? []
    return Array(
        Set(
            matches.compactMap { match in
                guard let captureRange = Range(match.range(at: 0), in: value) else {
                    return nil
                }
                return String(value[captureRange])
            }
        )
    ).sorted()
}

private struct NamingSemanticMatch {
    let field_key: String
    let source_key: String
    let source_value: String
    let corrected_value: String
    let score: Double
}

private func semanticFeedbackMatches(
    correctedFields: [String: String],
    sourceFields: [String: String],
    analysis: AnalysisResponse?
) -> [NamingSemanticMatch] {
    guard !correctedFields.isEmpty else {
        return []
    }
    let candidates = semanticSourceCandidates(sourceFields: sourceFields, analysis: analysis)
    guard !candidates.isEmpty else {
        return []
    }

    var matches: [NamingSemanticMatch] = []
    for (fieldKey, correctedValue) in correctedFields {
        let correctedTrimmed = correctedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correctedTrimmed.isEmpty else {
            continue
        }
        guard let pool = candidates[fieldKey], !pool.isEmpty else {
            continue
        }
        let best = pool.max { lhs, rhs in
            semanticScore(for: fieldKey, correctedValue: correctedTrimmed, sourceValue: lhs.value)
                < semanticScore(for: fieldKey, correctedValue: correctedTrimmed, sourceValue: rhs.value)
        }
        guard let best else { continue }
        let bestScore = semanticScore(for: fieldKey, correctedValue: correctedTrimmed, sourceValue: best.value)
        guard bestScore >= semanticThreshold(for: fieldKey) else {
            continue
        }
        matches.append(
            NamingSemanticMatch(
                field_key: fieldKey,
                source_key: best.source_key,
                source_value: best.value,
                corrected_value: correctedTrimmed,
                score: bestScore
            )
        )
    }
    return matches
}

private func semanticSourceCandidates(
    sourceFields: [String: String],
    analysis: AnalysisResponse?
) -> [String: [(source_key: String, value: String)]] {
    var result: [String: [(source_key: String, value: String)]] = [:]

    func appendCandidate(_ fieldKey: String, sourceKey: String, value: String?) {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return
        }
        let normalized = FilenameGuardrails.normalizeFrenchTypography(raw)
        guard !normalized.isEmpty else {
            return
        }
        var list = result[fieldKey] ?? []
        if !list.contains(where: { normalizedFeedbackToken($0.value) == normalizedFeedbackToken(normalized) }) {
            list.append((source_key: sourceKey, value: normalized))
        }
        result[fieldKey] = list
    }

    for (key, value) in sourceFields {
        appendCandidate(key, sourceKey: "source_fields.\(key)", value: value)
    }

    guard let analysis else {
        return result
    }

    for (key, value) in analysis.champs {
        appendCandidate(key, sourceKey: "analysis.\(key)", value: value)
    }

    let aliasesByField: [String: [String]] = [
        "titre": ["objet", "document_objet", "resolution_titre", "summary.title", "summary.generated", "metadata.objet"],
        "objet": ["titre", "document_objet", "resolution_titre", "summary.title", "summary.generated", "metadata.objet"],
        "cocontractant": ["organisme_emetteur", "metadata.organisme_emetteur", "comite"],
        "date": ["date_document", "metadata.date_document", "date"],
        "date_document": ["date", "metadata.date_document", "date_document"],
        "numero": ["numero_document", "metadata.numero_document", "numero"],
        "periode": ["date_document", "date", "periode"]
    ]

    for (fieldKey, aliases) in aliasesByField {
        for alias in aliases {
            appendCandidate(fieldKey, sourceKey: "analysis.\(alias)", value: analysis.champs[alias] ?? sourceFields[alias])
        }
    }

    return result
}

private func semanticScore(for fieldKey: String, correctedValue: String, sourceValue: String) -> Double {
    switch fieldKey {
    case "date", "date_document", "periode":
        let correctedYears = extractSemanticYears(correctedValue)
        let sourceYears = extractSemanticYears(sourceValue)
        if !correctedYears.isEmpty && correctedYears == sourceYears {
            return 1.0
        }
        if !correctedYears.isEmpty && !sourceYears.isEmpty && !Set(correctedYears).intersection(Set(sourceYears)).isEmpty {
            return 0.8
        }
        return feedbackSimilarityScore(correctedValue, sourceValue)
    case "numero":
        let correctedNumber = extractSemanticDocumentNumber(correctedValue)
        let sourceNumber = extractSemanticDocumentNumber(sourceValue)
        if let correctedNumber, let sourceNumber, correctedNumber == sourceNumber {
            return 1.0
        }
        return feedbackSimilarityScore(correctedValue, sourceValue)
    default:
        return feedbackSimilarityScore(correctedValue, sourceValue)
    }
}

private func semanticThreshold(for fieldKey: String) -> Double {
    switch fieldKey {
    case "titre", "objet", "cocontractant":
        return 0.42
    case "date", "date_document", "periode", "numero":
        return 0.60
    default:
        return 0.70
    }
}

private func extractSemanticYears(_ value: String) -> [Int] {
    let regex = try? NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex?.matches(in: value, range: range).compactMap { match in
        guard let swiftRange = Range(match.range, in: value) else {
            return nil
        }
        return Int(value[swiftRange])
    } ?? []
}

private func extractSemanticDocumentNumber(_ value: String) -> String? {
    let regex = try? NSRegularExpression(pattern: #"\b(19|20)\d{2}\s*[-–]\s*\d{1,4}\b"#)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex?.firstMatch(in: value, range: range),
          let swiftRange = Range(match.range, in: value) else {
        return nil
    }
    return normalizedFeedbackToken(String(value[swiftRange]))
}

private func mergedFeedbackNotes(
    baseNotes: String?,
    semanticMatches: [NamingSemanticMatch]
) -> String? {
    let trimmedBase = baseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !semanticMatches.isEmpty else {
        return trimmedBase?.isEmpty == true ? nil : trimmedBase
    }

    let semanticSummary = semanticMatches
        .sorted { lhs, rhs in
            if lhs.field_key == rhs.field_key {
                return lhs.score > rhs.score
            }
            return lhs.field_key < rhs.field_key
        }
        .map { match in
            let score = String(format: "%.2f", match.score)
            return match.field_key + " <= " + match.source_key + " (" + score + ")"
        }
        .joined(separator: "; ")

    let notePrefix = "auto_semantic_compare[\(semanticSummary)]"
    if let trimmedBase, !trimmedBase.isEmpty {
        return "\(trimmedBase)\n\(notePrefix)"
    }
    return notePrefix
}
