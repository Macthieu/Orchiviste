import Foundation

struct IDPPipelineOutput: Sendable {
    let relevantPages: [Int]
    let hasTableLayout: Bool
    let titleHints: [String]
    let clauseAttenduQueCount: Int
    let clauseResoluCount: Int
    let semanticFields: [String: String]
    let validationFlags: [String]
    let completenessScore: Double
}

enum IDPSemanticPipeline {
    static func run(
        request: AnalysisRequest,
        typeDoc: String,
        baseFields: [String: String]
    ) -> IDPPipelineOutput {
        let rawText = request.text ?? ""
        let pages = splitPages(rawText)
        let normalizedPages = pages.map(normalize)
        let normalizedAll = normalize(rawText)

        let relevantPages = detectRelevantPages(
            normalizedPages: normalizedPages,
            typeDoc: typeDoc
        )
        let hasTableLayout = detectTableLayout(rawText: rawText)
        let titleHints = detectTitleHints(rawText: rawText)
        let clauseAttenduQueCount = countMatches(
            in: normalizedAll,
            pattern: #"\battendu\s+que\b"#
        )
        let clauseResoluCount = countMatches(
            in: normalizedAll,
            pattern: #"\bil\s+est\s+resolu\b"#
        )
        let semanticFields = extractSemanticFields(rawText: rawText, typeDoc: typeDoc)
        let validation = validate(
            typeDoc: typeDoc,
            baseFields: baseFields,
            semanticFields: semanticFields,
            clauseResoluCount: clauseResoluCount
        )

        var fields = semanticFields
        fields["idp_pages_pertinentes"] = relevantPages.map(String.init).joined(separator: ",")
        fields["idp_layout_has_table"] = hasTableLayout ? "true" : "false"
        fields["idp_titles"] = titleHints.joined(separator: " | ")
        fields["idp_clause_attendu_que_count"] = "\(clauseAttenduQueCount)"
        fields["idp_clause_resolu_count"] = "\(clauseResoluCount)"
        fields["idp_validation_completude"] = String(format: "%.2f", validation.completeness)
        fields["idp_validation_flags"] = validation.flags.joined(separator: ";")
        fields["idp_action"] = suggestedAction(
            totalPages: pages.count,
            relevantPages: relevantPages,
            typeDoc: typeDoc
        )

        return IDPPipelineOutput(
            relevantPages: relevantPages,
            hasTableLayout: hasTableLayout,
            titleHints: titleHints,
            clauseAttenduQueCount: clauseAttenduQueCount,
            clauseResoluCount: clauseResoluCount,
            semanticFields: fields,
            validationFlags: validation.flags,
            completenessScore: validation.completeness
        )
    }

    private static func splitPages(_ text: String) -> [String] {
        guard !text.isEmpty else {
            return [""]
        }
        let pages = text.components(separatedBy: "\u{0C}")
        return pages.isEmpty ? [text] : pages
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func detectRelevantPages(normalizedPages: [String], typeDoc: String) -> [Int] {
        let tokens: [String]
        switch typeDoc {
        case "Facture":
            tokens = ["facture", "invoice", "montant", "total", "tps", "tvq", "fournisseur"]
        case "Resolution":
            tokens = ["resolution", "attendu que", "il est resolu", "adopte", "propose"]
        case "ProcesVerbal":
            tokens = ["proces-verbal", "seance", "ordre du jour", "comite", "decision"]
        default:
            tokens = ["signature", "date", "numero"]
        }

        var result: [Int] = []
        for (index, page) in normalizedPages.enumerated() {
            if tokens.contains(where: { page.contains($0) }) {
                result.append(index + 1)
            }
        }
        if result.isEmpty {
            return [1]
        }
        return Array(result.prefix(8))
    }

    private static func detectTableLayout(rawText: String) -> Bool {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return false
        }

        let structuredLineCount = lines.reduce(into: 0) { partial, line in
            let tabLike = line.contains("\t") || line.contains("|")
            let multiSpaces = line.range(of: #"\S+\s{2,}\S+"#, options: .regularExpression) != nil
            if tabLike || multiSpaces {
                partial += 1
            }
        }
        return structuredLineCount >= 2
    }

    private static func detectTitleHints(rawText: String) -> [String] {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(25)

        var titles: [String] = []
        for line in lines {
            guard line.count >= 5, line.count <= 140 else {
                continue
            }
            let letters = line.filter { $0.isLetter }
            guard !letters.isEmpty else {
                continue
            }
            let uppercaseLetters = letters.filter { $0.isUppercase }
            let uppercaseRatio = Double(uppercaseLetters.count) / Double(letters.count)
            if uppercaseRatio >= 0.65 {
                titles.append(line)
            }
            if titles.count == 3 {
                break
            }
        }
        return titles
    }

    private static func extractSemanticFields(rawText: String, typeDoc: String) -> [String: String] {
        var fields: [String: String] = [:]

        if let amount = firstMatch(
            in: rawText,
            pattern: #"(?i)\b(?:montant(?:\s+total)?|total)\s*[:\-]?\s*([$€]?\s?[0-9]{1,3}(?:[ \u00A0.,][0-9]{3})*(?:[.,][0-9]{2})?)\b"#
        ) {
            fields["montant_total"] = amount
        }

        if let resolutionTitle = firstMatch(
            in: rawText,
            pattern: #"(?im)^\s*(r[eé]solution[^\n\r]{0,120})$"#
        ) {
            fields["resolution_titre"] = resolutionTitle
        }

        if let resolutionNumber = firstMatch(
            in: rawText,
            pattern: #"(?i)\b(?:r[eé]s(?:olution)?)\s*[:#\-]?\s*([0-9]{2,4}(?:[-/][0-9]{1,4})?)\b"#
        ) {
            fields["resolution_numero"] = resolutionNumber
        }

        if fields["doc_type_hint"] == nil {
            fields["doc_type_hint"] = typeDoc
        }

        return fields
    }

    private static func validate(
        typeDoc: String,
        baseFields: [String: String],
        semanticFields: [String: String],
        clauseResoluCount: Int
    ) -> (flags: [String], completeness: Double) {
        var flags: [String] = []
        var requiredChecks: [(String, Bool)] = []

        switch typeDoc {
        case "Facture":
            requiredChecks = [
                ("numero", nonEmpty(baseFields["numero"]) != nil),
                ("date", nonEmpty(baseFields["date"]) != nil),
                ("montant_total", nonEmpty(semanticFields["montant_total"]) != nil)
            ]
        case "Resolution":
            requiredChecks = [
                ("date", nonEmpty(baseFields["date"]) != nil),
                ("numero", nonEmpty(baseFields["numero"]) != nil || nonEmpty(semanticFields["resolution_numero"]) != nil),
                ("clause_resolu", clauseResoluCount > 0)
            ]
        case "ProcesVerbal":
            requiredChecks = [
                ("date", nonEmpty(baseFields["date"]) != nil),
                ("comite", nonEmpty(baseFields["comite"]) != nil)
            ]
        default:
            requiredChecks = [
                ("date_or_numero", nonEmpty(baseFields["date"]) != nil || nonEmpty(baseFields["numero"]) != nil)
            ]
        }

        var passed = 0
        for check in requiredChecks {
            if check.1 {
                passed += 1
            } else {
                flags.append("missing_\(check.0)")
            }
        }

        let completeness: Double
        if requiredChecks.isEmpty {
            completeness = 1.0
        } else {
            completeness = Double(passed) / Double(requiredChecks.count)
        }
        return (flags, completeness)
    }

    private static func suggestedAction(totalPages: Int, relevantPages: [Int], typeDoc: String) -> String {
        if totalPages > relevantPages.count && relevantPages.count <= 2 {
            return "separer_pages_pertinentes"
        }
        if typeDoc == "Facture" {
            return "valider_montants_et_router"
        }
        if typeDoc == "Resolution" {
            return "extraire_clauses_et_router"
        }
        if typeDoc == "ProcesVerbal" {
            return "structurer_sections_et_router"
        }
        return "router_standard"
    }

    private static func countMatches(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
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

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
