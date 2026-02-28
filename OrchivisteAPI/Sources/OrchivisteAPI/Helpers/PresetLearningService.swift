import Foundation
import Vapor

enum PresetLearningService {
    static func learn(request: PresetLearnRequest, logger: Logger) throws -> PresetLearnResponse {
        let folderURL = URL(fileURLWithPath: request.folder_path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw Abort(.badRequest, reason: "Le dossier source est introuvable.")
        }

        let allowedExtensions = normalizeExtensions(request.extensions)
        let sampleSize = max(1, min(200, request.sample_size ?? 30))
        let allFiles = try collectFiles(in: folderURL, allowedExtensions: allowedExtensions)
        guard !allFiles.isEmpty else {
            throw Abort(.badRequest, reason: "Aucun document supporte trouve dans le dossier.")
        }

        let sampleFiles = Array(allFiles.prefix(sampleSize))
        let observations = sampleFiles.compactMap { fileURL -> LearnedDocumentObservation? in
            guard let extracted = DocumentTextExtractor.extract(fileURL: fileURL, logger: logger) else {
                return nil
            }
            let mergedText = extracted.pages.joined(separator: "\n\u{000C}\n")
            return LearnedDocumentObservation(
                fileURL: fileURL,
                text: mergedText,
                pages: max(1, extracted.pages.count),
                fileExtension: fileURL.pathExtension.lowercased(),
                fileName: fileURL.lastPathComponent,
                warnings: extracted.warnings
            )
        }

        guard !observations.isEmpty else {
            throw Abort(.badRequest, reason: "Extraction impossible sur les documents echantillonnes.")
        }

        let detectedTokens = topRecurringTokens(in: observations)
        let inferredTypes = inferDocumentTypes(in: observations)
        let structureHints = inferStructureHints(in: observations)
        let suggestedFields = buildSuggestedFields(from: observations)
        let inferredClassCode = inferClassCode(from: observations)
        let proposedTemplate = buildTemplate(from: suggestedFields, inferredTypes: inferredTypes)
        let normalizationRules = [
            "trim",
            "collapse_spaces",
            "remove_technical_mentions",
            "max_256_chars"
        ]
        let exampleRenames = buildRenameExamples(
            from: observations,
            suggestedFields: suggestedFields,
            template: proposedTemplate,
            inferredTypes: inferredTypes
        )

        let fieldConfidence = suggestedFields.isEmpty
            ? 0.25
            : suggestedFields.map(\.confidence).reduce(0, +) / Double(suggestedFields.count)
        let typeConfidence = inferredTypes.isEmpty ? 0.25 : min(0.95, 0.45 + Double(inferredTypes.count) * 0.1)
        let examplesConfidence = exampleRenames.contains(where: { $0.after != nil }) ? 0.8 : 0.3
        let confidence = min(0.95, max(0.2, (fieldConfidence * 0.5) + (typeConfidence * 0.25) + (examplesConfidence * 0.25)))

        var warnings: [String] = []
        if proposedTemplate == nil {
            warnings.append("template_insufficient_signal")
        }
        if inferredClassCode == nil {
            warnings.append("class_code_needs_review")
        }
        if suggestedFields.isEmpty {
            warnings.append("field_extraction_needs_review")
        }
        if inferredTypes.isEmpty {
            warnings.append("document_type_needs_review")
        }
        if exampleRenames.allSatisfy({ $0.after == nil }) {
            warnings.append("rename_examples_needs_review")
        }
        if observations.contains(where: { !$0.warnings.isEmpty }) {
            warnings.append("source_extraction_limited")
        }

        let needsReview = confidence < 0.72 || !warnings.isEmpty
        let timestamp = draftTimestamp()
        let draftID = "draft_\(timestamp)"
        let folderLabel = folderURL.lastPathComponent.isEmpty ? "Preset brouillon" : folderURL.lastPathComponent
        let suggestedFieldKeys = suggestedFields.filter { $0.confidence >= 0.55 }.map(\.key)
        let preset = Preset(
            id: draftID,
            name: "Draft \(folderLabel)",
            name_format: proposedTemplate ?? "{type_doc}-{date}-{numero}",
            class_code: inferredClassCode,
            postprocess: ["trim"],
            version: "draft-\(timestamp)",
            description: "Preset draft learned from folder \(folderURL.lastPathComponent)",
            detect: PresetDetect(
                signals_any: Array(detectedTokens.prefix(6)),
                regex_any: suggestedFields.compactMap { field in
                    field.strategies.first(where: { $0.kind == "regex" })?.pattern
                }
            ),
            extract: PresetExtract(fields: suggestedFields.map {
                PresetExtractField(
                    key: $0.key,
                    label: $0.key.replacingOccurrences(of: "_", with: " ").capitalized,
                    required: $0.confidence >= 0.7,
                    strategies: $0.strategies,
                    notes: $0.notes
                )
            }),
            naming: PresetNaming(
                template: proposedTemplate ?? "{type_doc}-{date}-{numero}",
                normalization: normalizationRules,
                postprocess: ["trim"],
                notes: [
                    "Le nom final doit rester significatif, precis et concis.",
                    "Ne jamais inclure de mentions techniques dans le nom final."
                ]
            ),
            classification: PresetClassification(
                suggested_class_code: inferredClassCode,
                rules: inferredTypes.prefix(2).map {
                    PresetClassificationRule(
                        when_signal: $0,
                        when_regex: nil,
                        when_type_doc: $0,
                        assign_class_code: inferredClassCode,
                        notes: ["Regle proposee automatiquement, a valider."]
                    )
                }
            ),
            export: PresetExport(
                preferred_pdf: PresetPreferredPDF(format: "PDF/A-2b", enabled: true)
            ),
            review: PresetReview(
                min_confidence: max(0.72, min(0.9, confidence + 0.08)),
                required_fields: suggestedFieldKeys.isEmpty ? ["type_doc", "date", "numero"] : suggestedFieldKeys
            )
        )

        let fileName = "draft.\(timestamp).json"
        let savedPath = try ConfigLoader.savePreset(preset, filename: fileName)

        return PresetLearnResponse(
            preset: preset,
            saved_path: savedPath.path,
            confidence: confidence,
            needs_review: needsReview,
            report: PresetLearnReport(
                scanned_files: allFiles.count,
                sampled_files: observations.count,
                extensions: allowedExtensions,
                detected_tokens: Array(detectedTokens.prefix(12)),
                document_types: inferredTypes,
                structure_hints: structureHints,
                suggested_fields: suggestedFields,
                proposed_name_template: proposedTemplate,
                normalization_rules: normalizationRules,
                examples_before_after: Array(exampleRenames.prefix(10)),
                warnings: warnings
            )
        )
    }

    private static func normalizeExtensions(_ raw: [String]?) -> [String] {
        let normalized = (raw ?? DocumentTextExtractor.supportedExtensions())
            .map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
                    .lowercased()
            }
            .filter { DocumentTextExtractor.supportedExtensions().contains($0) }
        return normalized.isEmpty ? DocumentTextExtractor.supportedExtensions() : Array(Set(normalized)).sorted()
    }

    private static func collectFiles(in root: URL, allowedExtensions: [String]) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let allowed = Set(allowedExtensions)
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }
            guard allowed.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func topRecurringTokens(in observations: [LearnedDocumentObservation]) -> [String] {
        let stopwords: Set<String> = [
            "avec", "dans", "pour", "from", "this", "that", "document", "dossier",
            "fichier", "page", "pages", "ville", "municipalite", "service",
            "local", "sharepoint", "orchiviste", "analyse", "preview"
        ]
        var counts: [String: Int] = [:]
        for observation in observations {
            let normalized = normalize(observation.fileName + " " + observation.text)
            for token in normalized.split(separator: " ").map(String.init) {
                guard token.count >= 4 else { continue }
                guard !stopwords.contains(token) else { continue }
                guard !token.allSatisfy(\.isNumber) else { continue }
                counts[token, default: 0] += 1
            }
        }
        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .map(\.key)
    }

    private static func inferDocumentTypes(in observations: [LearnedDocumentObservation]) -> [String] {
        var counts: [String: Int] = [:]
        for observation in observations {
            let merged = normalize(observation.fileName + " " + observation.text)
            let inferred: String?
            if merged.contains("resolution") || merged.contains("resolu") {
                inferred = "Resolution"
            } else if merged.contains("proces verbal") || merged.contains("ordre du jour") {
                inferred = "ProcesVerbal"
            } else if merged.contains("facture") || merged.contains("invoice") {
                inferred = "Facture"
            } else if merged.contains("contrat") || merged.contains("entente") || merged.contains("bail") {
                inferred = "Contrat"
            } else if merged.contains("presentation") || observation.fileExtension == "pptx" {
                inferred = "Presentation"
            } else {
                inferred = nil
            }
            if let inferred {
                counts[inferred, default: 0] += 1
            }
        }
        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .map(\.key)
    }

    private static func inferStructureHints(in observations: [LearnedDocumentObservation]) -> [String] {
        var hints = Set<String>()
        for observation in observations {
            let normalized = normalize(observation.text)
            if normalized.contains("signature") || normalized.contains("signe") {
                hints.insert("signature")
            }
            if normalized.contains("attendu que") {
                hints.insert("clause_attendu_que")
            }
            if normalized.contains("il est resolu") || normalized.contains("resolu") {
                hints.insert("clause_resolu")
            }
            if normalized.contains("tableau") || normalized.contains("montant") {
                hints.insert("table_like_sections")
            }
            if observation.pages > 1 {
                hints.insert("multi_pages")
            }
        }
        return hints.sorted()
    }

    private static func buildSuggestedFields(from observations: [LearnedDocumentObservation]) -> [PresetLearnSuggestedField] {
        let dateMatches = observations.compactMap { extractDate(from: $0.text) }
        let numberMatches = observations.compactMap { extractNumber(from: $0.text) ?? extractNumber(from: $0.fileName) }
        let organismeMatches = observations.compactMap { extractOrganisme(from: $0.text) }
        let sujetMatches = observations.compactMap { extractSujet(from: $0.text) ?? extractSujet(from: $0.fileName) }

        var fields: [PresetLearnSuggestedField] = []
        if !dateMatches.isEmpty {
            fields.append(
                PresetLearnSuggestedField(
                    key: "date",
                    confidence: confidence(for: dateMatches.count, total: observations.count),
                    strategies: [
                        PresetExtractStrategy(
                            kind: "regex",
                            pattern: #"(?i)\b(20\d{2}[-/]\d{2}[-/]\d{2}|\d{4}-\d{2}-\d{2}|\d{4}\.\d{2}\.\d{2})\b"#,
                            semantic_hint: nil,
                            examples: Array(dateMatches.prefix(3)),
                            notes: ["Date detectee de maniere recurrente."]
                        )
                    ],
                    notes: ["Champ observe dans plusieurs documents du dossier."]
                )
            )
        }
        if !numberMatches.isEmpty {
            fields.append(
                PresetLearnSuggestedField(
                    key: "numero",
                    confidence: confidence(for: numberMatches.count, total: observations.count),
                    strategies: [
                        PresetExtractStrategy(
                            kind: "regex",
                            pattern: #"(?i)\b(?:res(?:olution)?|pv|contrat|fac(?:ture)?)?[-\s#:]?([A-Z0-9]{2,}(?:[-/][A-Z0-9]{1,8})+|[A-Z]{1,4}-\d{2,6})\b"#,
                            semantic_hint: nil,
                            examples: Array(numberMatches.prefix(3)),
                            notes: ["Numero detecte de maniere recurrente."]
                        )
                    ],
                    notes: ["Verifier la granularite du numero propose."]
                )
            )
        }
        if !organismeMatches.isEmpty {
            fields.append(
                PresetLearnSuggestedField(
                    key: "organisme",
                    confidence: confidence(for: organismeMatches.count, total: observations.count),
                    strategies: [
                        PresetExtractStrategy(
                            kind: "semantic",
                            pattern: nil,
                            semantic_hint: "organisme_emetteur",
                            examples: Array(organismeMatches.prefix(3)),
                            notes: ["Nom d'organisme detecte dans l'entete ou le texte."]
                        )
                    ],
                    notes: ["Champ semantique, a valider humainement."]
                )
            )
        }
        if !sujetMatches.isEmpty {
            fields.append(
                PresetLearnSuggestedField(
                    key: "sujet",
                    confidence: confidence(for: sujetMatches.count, total: observations.count) * 0.9,
                    strategies: [
                        PresetExtractStrategy(
                            kind: "semantic",
                            pattern: nil,
                            semantic_hint: "titre_ou_objet",
                            examples: Array(sujetMatches.prefix(3)),
                            notes: ["Sujet suggere depuis le titre ou le nom de fichier."]
                        )
                    ],
                    notes: ["Le sujet peut varier et doit rester concis."]
                )
            )
        }
        return fields.sorted { $0.confidence > $1.confidence }
    }

    private static func inferClassCode(from observations: [LearnedDocumentObservation]) -> String? {
        var counts: [String: Int] = [:]
        let pattern = #"^([A-Za-z]{2,}(?:-[A-Za-z0-9]{1,6})?|[0-9]{3,4}(?:-[0-9]{2})?)"#
        for observation in observations {
            if let match = firstRegexMatch(in: observation.fileName, pattern: pattern) {
                counts[match.uppercased(), default: 0] += 1
            }
        }
        guard let winner = counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) else {
            return nil
        }
        let minHits = max(2, Int(ceil(Double(observations.count) * 0.35)))
        return winner.value >= minHits ? winner.key : nil
    }

    private static func buildTemplate(
        from fields: [PresetLearnSuggestedField],
        inferredTypes: [String]
    ) -> String? {
        let fieldKeys = Set(fields.filter { $0.confidence >= 0.55 }.map(\.key))
        guard fieldKeys.contains("date") || fieldKeys.contains("numero") || fieldKeys.contains("sujet") else {
            return nil
        }

        var parts: [String] = []
        if !inferredTypes.isEmpty {
            parts.append("{type_doc}")
        }
        if fieldKeys.contains("date") {
            parts.append("{date}")
        }
        if fieldKeys.contains("numero") {
            parts.append("{numero}")
        }
        if fieldKeys.contains("sujet") {
            parts.append("{sujet}")
        }
        if parts.isEmpty {
            return nil
        }
        return parts.joined(separator: "-")
    }

    private static func buildRenameExamples(
        from observations: [LearnedDocumentObservation],
        suggestedFields: [PresetLearnSuggestedField],
        template: String?,
        inferredTypes: [String]
    ) -> [PresetLearnExampleRename] {
        guard let template else {
            return observations.prefix(10).map {
                PresetLearnExampleRename(before: $0.fileName, after: nil)
            }
        }

        let fieldKeys = Set(suggestedFields.filter { $0.confidence >= 0.55 }.map(\.key))
        let dominantType = inferredTypes.first ?? "Document"

        return observations.prefix(10).map { observation in
            let date = fieldKeys.contains("date") ? extractDate(from: observation.text) : nil
            let number = fieldKeys.contains("numero")
                ? (extractNumber(from: observation.text) ?? extractNumber(from: observation.fileName))
                : nil
            let sujet = fieldKeys.contains("sujet")
                ? (extractSujet(from: observation.text) ?? extractSujet(from: observation.fileName))
                : nil

            let required = [
                template.contains("{date}") ? date : "ok",
                template.contains("{numero}") ? number : "ok",
                template.contains("{sujet}") ? sujet : "ok"
            ]
            if required.contains(where: { $0 == nil }) {
                return PresetLearnExampleRename(before: observation.fileName, after: nil)
            }

            let ext = URL(fileURLWithPath: observation.fileName).pathExtension
            let values: [String: String] = [
                "{type_doc}": dominantType,
                "{date}": date ?? "",
                "{numero}": number ?? "",
                "{sujet}": sujet ?? ""
            ]
            var candidate = template
            for (token, value) in values {
                candidate = candidate.replacingOccurrences(of: token, with: value)
            }
            candidate = NamingPolicy.normalizedStem(candidate)
            candidate = candidate.replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            candidate = candidate.replacingOccurrences(
                of: #"-{2,}"#,
                with: "-",
                options: .regularExpression
            )
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            let withExtension = ext.isEmpty ? candidate : "\(candidate).\(ext)"
            let finalName = NamingPolicy.truncateFileNameIfNeeded(withExtension)
            if finalName.isEmpty || NamingPolicy.containsTechnicalMention(finalName) {
                return PresetLearnExampleRename(before: observation.fileName, after: nil)
            }
            return PresetLearnExampleRename(before: observation.fileName, after: finalName)
        }
    }

    private static func extractDate(from text: String) -> String? {
        firstRegexMatch(
            in: text,
            pattern: #"(?i)\b(20\d{2}[-/.]\d{2}[-/.]\d{2}|\d{4}-\d{2}-\d{2})\b"#
        )
            .map { $0.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-") }
    }

    private static func extractNumber(from text: String) -> String? {
        firstRegexMatch(
            in: text,
            pattern: #"(?i)\b([A-Z]{1,4}-\d{2,6}|\d{2,4}(?:[-/]\d{1,6})+)\b"#
        )
    }

    private static func extractOrganisme(from text: String) -> String? {
        firstRegexMatch(
            in: text,
            pattern: #"(?im)\b(?:ville|municipalite|municipality|service|organisme)\s+(?:de|du|des|d')?\s*([A-Z][A-Za-z' -]{2,80})"#
        )
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func extractSujet(from text: String) -> String? {
        let title = firstRegexMatch(
            in: text,
            pattern: #"(?im)^\s*(?:objet|sujet|titre)\s*[:\-]\s*([^\n\r]{4,120})"#
        )
        if let title, !NamingPolicy.containsTechnicalMention(title) {
            return sanitizeSujet(title)
        }
        let firstLine = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if firstLine.count >= 4 && firstLine.count <= 120 {
            let stem = URL(fileURLWithPath: firstLine).deletingPathExtension().lastPathComponent
            if !stem.isEmpty {
                return sanitizeSujet(stem)
            }
        }
        return nil
    }

    private static func sanitizeSujet(_ raw: String) -> String {
        NamingPolicy.normalizedStem(
            raw.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: #"\b(?:draft|brouillon|final|version)\b"#, with: "", options: .regularExpression)
        )
    }

    private static func confidence(for count: Int, total: Int) -> Double {
        guard total > 0 else { return 0.2 }
        let ratio = Double(count) / Double(total)
        return min(0.95, max(0.25, ratio))
    }

    private static func draftTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
    }

    private static func firstRegexMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let swiftRange = Range(targetRange, in: text) else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LearnedDocumentObservation {
    let fileURL: URL
    let text: String
    let pages: Int
    let fileExtension: String
    let fileName: String
    let warnings: [String]
}
