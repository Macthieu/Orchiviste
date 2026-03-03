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
        let rules = ConfigLoader.loadNamingRules()
        let rule = request.naming_rule_id.flatMap { ConfigLoader.loadNamingRule(id: $0) }
            ?? selectNamingRuleForRouting(job: job, analysis: analysis, preset: preset, rules: rules)
        guard let rule else {
            throw Abort(.notFound, reason: "Aucune règle de nommage exploitable pour cette tâche.")
        }

        var thesaurus = ConfigLoader.loadNamingThesauri().first ?? NamingFoundationSeeds.defaultThesaurus()
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
            if shouldUseOverlayField(key: key, existing: extracted[key], incoming: value) {
                extracted[key] = value
            }
        }
        let normalized = engine.normalizeFields(extracted, rule: rule, thesaurus: thesaurus)
        let correctedFields = parseFields(from: correctedFileName, template: rule.template)

        var learnedAliases: [String] = []
        let candidateFieldKeys = ["titre", "objet", "cocontractant"]
        for key in candidateFieldKeys {
            guard let sourceValue = normalized[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let correctedValue = correctedFields[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sourceValue.isEmpty,
                  !correctedValue.isEmpty,
                  normalizedFeedbackToken(sourceValue) != normalizedFeedbackToken(correctedValue) else {
                continue
            }
            thesaurus = upsertingFeedbackAlias(
                in: thesaurus,
                sourceValue: sourceValue,
                correctedValue: correctedValue,
                fieldKey: key
            )
            learnedAliases.append("\(sourceValue) -> \(correctedValue)")
        }

        let preservedAcronyms = extractUppercaseAcronyms(from: correctedFields["titre"] ?? correctedFields["objet"] ?? "")
        let updatedRule = appendFeedback(
            to: rule,
            sourceFileName: sourceURL.lastPathComponent,
            correctedFileName: correctedFileName,
            sourceFields: normalized,
            correctedFields: correctedFields,
            notes: request.notes,
            preservedAcronyms: preservedAcronyms
        )

        try ConfigLoader.saveNamingRule(updatedRule)
        try ConfigLoader.saveNamingThesaurus(thesaurus)

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
        pattern += NSRegularExpression.escapedPattern(for: String(template[cursor..<fullRange.lowerBound]))
        pattern += "(.+?)"
        fieldKeys.append(String(template[keyRange]))
        cursor = fullRange.upperBound
    }
    pattern += NSRegularExpression.escapedPattern(for: String(template[cursor...]))
    pattern += "$"

    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
            in: fileName,
            range: NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
          ) else {
        return [:]
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

private func normalizedFeedbackToken(_ raw: String) -> String {
    raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
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
