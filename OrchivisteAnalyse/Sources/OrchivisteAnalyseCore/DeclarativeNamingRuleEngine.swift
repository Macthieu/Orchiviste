import Foundation
import OrchivisteSharedKit

public struct DeclarativeNamingRuleEngine: NamingRuleDetecting, NamingFieldExtracting, NamingFieldNormalizing, NamingFileRendering, NamingFileValidating {
    public init() {}

    public func validate(_ request: NamingRuleValidationRequest) -> NamingRuleValidationResult {
        let detected = detectRule(in: request.text, metadata: request.metadata, rules: [request.rule])
        let extracted = extractFields(from: request.text, rule: request.rule, metadata: request.metadata)
        let normalized = normalizeFields(extracted, rule: request.rule, thesaurus: request.thesaurus)
        let rendered = renderFilename(rule: request.rule, fields: normalized)
        let issues = validateFilename(rendered, rule: request.rule, fields: normalized)
        return NamingRuleValidationResult(
            detected_rule_id: detected?.id,
            extracted_fields: extracted,
            normalized_fields: normalized,
            rendered_filename: rendered,
            issues: issues
        )
    }

    public func detectRule(
        in text: String,
        metadata: NamingSourceMetadata?,
        rules: [NamingRuleDefinition]
    ) -> NamingRuleDefinition? {
        let haystack = normalizedSearchText([text, metadata?.fileName, metadata?.originalName].compactMap { $0 }.joined(separator: "\n"))
        var best: (rule: NamingRuleDefinition, score: Int)?
        for rule in rules {
            let signalScore = (rule.conditions.signals_any ?? []).reduce(into: 0) { partial, signal in
                if haystack.contains(normalizedSearchText(signal)) {
                    partial += 2
                }
            }
            let regexScore = (rule.conditions.regex_any ?? []).reduce(into: 0) { partial, pattern in
                if firstMatch(pattern: pattern, in: text) != nil {
                    partial += 3
                }
            }
            let sourceFamilyScore = (rule.conditions.source_document_families ?? []).reduce(into: 0) { partial, family in
                if haystack.contains(normalizedSearchText(family)) {
                    partial += 1
                }
            }
            let total = signalScore + regexScore + sourceFamilyScore
            guard total > 0 else { continue }
            if best == nil || total > best?.score ?? 0 {
                best = (rule, total)
            }
        }
        return best?.rule
    }

    public func extractFields(
        from text: String,
        rule: NamingRuleDefinition,
        metadata: NamingSourceMetadata?
    ) -> [String: String] {
        var fields: [String: String] = [:]
        for field in rule.fields {
            for strategy in field.strategies {
                if let value = extractValue(
                    from: text,
                    key: field.key,
                    strategy: strategy,
                    metadata: metadata
                ) {
                    fields[field.key] = value
                    break
                }
            }
        }
        return fields
    }

    public func normalizeFields(
        _ fields: [String: String],
        rule: NamingRuleDefinition,
        thesaurus: NamingThesaurus?
    ) -> [String: String] {
        var normalized: [String: String] = [:]
        let aliasMap = buildAliasMap(thesaurus)
        let stopwords = Set((thesaurus?.stopwords ?? []).map(normalizedSearchText))
        let preserve = Set((thesaurus?.preserve_terms ?? []).map(normalizedSearchText))

        for (key, rawValue) in fields {
            var value = FilenameGuardrails.normalizeFrenchTypography(rawValue)
            switch key {
            case "numero":
                value = normalizeDocumentNumber(value)
            case "date":
                value = normalizeDateString(value) ?? value
            case "periode":
                value = normalizePeriod(value)
            case "cocontractant":
                value = canonicalizePhrase(value, aliasMap: aliasMap)
                value = cleanupCounterparties(value)
            case "objet", "titre":
                value = canonicalizePhrase(value, aliasMap: aliasMap)
                value = cleanObjectPhrase(value, stopwords: stopwords, preserve: preserve)
            default:
                value = canonicalizePhrase(value, aliasMap: aliasMap)
            }

            if rule.document_family == "entente_uniformisee", key == "objet" {
                value = stripAgreementFamilyLeadIn(value)
            }
            normalized[key] = value
        }

        if rule.document_family == "entente_uniformisee",
           let existing = normalized["objet"] {
            normalized["objet"] = stripAgreementFamilyLeadIn(existing)
        }
        return normalized
    }

    public func renderFilename(
        rule: NamingRuleDefinition,
        fields: [String: String]
    ) -> String {
        var rendered = rule.template
        for (key, value) in fields {
            rendered = rendered.replacingOccurrences(of: "{\(key)}", with: value)
        }

        rendered = rendered.replacingOccurrences(of: #"\{[^}]+\}"#, with: "", options: .regularExpression)
        rendered = rendered.replacingOccurrences(of: #"\s*–\s*–\s*"#, with: " – ", options: .regularExpression)
        rendered = rendered.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        rendered = FilenameGuardrails.normalizeFrenchTypography(rendered)
        if !rendered.lowercased().hasSuffix(".pdf") {
            rendered += ".pdf"
        }
        return FilenameGuardrails.truncateFileNameIfNeeded(rendered)
    }

    public func validateFilename(
        _ filename: String,
        rule: NamingRuleDefinition,
        fields: [String: String]
    ) -> [NamingRuleValidationIssue] {
        var issues: [NamingRuleValidationIssue] = []

        if let error = FilenameGuardrails.validateCandidateStem(filename) {
            issues.append(.init(level: .error, code: "filename_guardrail", message: error))
        }

        for field in rule.fields where field.required {
            if fields[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(.init(
                    level: .error,
                    code: "missing_required_field",
                    message: "Le champ \(field.key) est requis.",
                    field: field.key
                ))
            }
        }

        let normalizedFilename = normalizedSearchText(filename)
        for forbidden in rule.forbidden_terms {
            if normalizedFilename.contains(normalizedSearchText(forbidden)) {
                issues.append(.init(
                    level: .error,
                    code: "forbidden_term",
                    message: "Le nom final contient un terme interdit: \(forbidden)."
                ))
            }
        }

        for validation in rule.validations {
            switch validation.kind {
            case "required_prefix":
                if let prefix = validation.parameter, !filename.hasPrefix(prefix) {
                    issues.append(.init(
                        level: .error,
                        code: "required_prefix",
                        message: validation.message ?? "Le nom doit commencer par \(prefix)."
                    ))
                }
            case "exclude_phrase":
                if let phrase = validation.parameter,
                   normalizedFilename.contains(normalizedSearchText(phrase)) {
                    issues.append(.init(
                        level: .error,
                        code: "exclude_phrase",
                        message: validation.message ?? "Le nom ne doit pas contenir \(phrase)."
                    ))
                }
            case "max_length":
                if filename.count > (Int(validation.parameter ?? "") ?? FilenameGuardrails.maxRecommendedLength) {
                    issues.append(.init(
                        level: .error,
                        code: "max_length",
                        message: validation.message ?? "Le nom dépasse la longueur recommandée."
                    ))
                }
            default:
                continue
            }
        }

        if issues.isEmpty {
            issues.append(.init(level: .info, code: "ok", message: "Validation réussie."))
        }
        return issues
    }

    private func extractValue(
        from text: String,
        key: String,
        strategy: NamingFieldStrategy,
        metadata: NamingSourceMetadata?
    ) -> String? {
        switch strategy.kind.lowercased() {
        case "regex":
            guard let pattern = strategy.pattern else { return nil }
            return firstMatch(pattern: pattern, in: text)
        case "semantic":
            return extractSemanticValue(from: text, key: key, hint: strategy.semantic_hint, metadata: metadata)
        default:
            return nil
        }
    }

    private func extractSemanticValue(
        from text: String,
        key: String,
        hint: String?,
        metadata: NamingSourceMetadata?
    ) -> String? {
        switch hint ?? key {
        case "resolution_number":
            return firstMatch(pattern: #"(?i)r[ée]solution\s*n[°o]?\s*([0-9]{4}-[0-9]{1,4})"#, in: text)
        case "resolution_title":
            return extractResolutionTitle(from: text)
        case "adoption_date":
            return extractAdoptionDate(from: text)
        case "agreement_counterparty":
            return extractAgreementCounterparty(from: text, metadata: metadata)
        case "agreement_object":
            return extractAgreementObject(from: text)
        case "agreement_period":
            return extractAgreementPeriod(from: text)
        default:
            return nil
        }
    }

    private func extractResolutionTitle(from text: String) -> String? {
        let lines = significantLines(from: text)
        for (index, line) in lines.enumerated() {
            if normalizedSearchText(line).contains("resolution"),
               index + 1 < lines.count {
                let candidate = lines[index + 1]
                if candidate.count >= 8 {
                    return candidate
                }
            }
        }
        return significantUppercaseLine(in: text)
    }

    private func extractAdoptionDate(from text: String) -> String? {
        if let iso = firstMatch(pattern: #"\b(20[0-9]{2}-[01][0-9]-[0-3][0-9])\b"#, in: text),
           let normalized = normalizeDateString(iso) {
            return normalized
        }

        let patterns = [
            #"(?i)\b([0-3]?[0-9]\s+(?:janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre)\s+20[0-9]{2})\b"#,
            #"(?i)\b(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+([0-3]?[0-9]\s+(?:janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre)\s+20[0-9]{2})\b"#
        ]
        for pattern in patterns {
            if let raw = firstMatch(pattern: pattern, in: text),
               let normalized = normalizeDateString(raw) {
                return normalized
            }
        }
        return nil
    }

    private func extractAgreementCounterparty(from text: String, metadata: NamingSourceMetadata?) -> String? {
        let patterns = [
            #"(?i)(?:entre|avec)\s+(?:la\s+)?ville\s+d[' ]amos\s+et\s+([^,\n.;:]+)"#,
            #"(?i)([^,\n.;:]+?)\s+(?:et|,)\s+(?:la\s+)?ville\s+d[' ]amos"#
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text) {
                return cleanupCounterparties(match)
            }
        }

        if let fileName = metadata?.fileName,
           let match = firstMatch(pattern: #"(?i)([A-Za-zÀ-ÿ0-9 '&.-]{3,})\s*[-–]\s*Entente"#, in: fileName) {
            return cleanupCounterparties(match)
        }

        let organizationHints = significantLines(from: text)
            .filter { $0.range(of: #"(?i)\b(?:inc\.?|lt[ée]e?|s\.?e\.?n\.?c\.?|compagnie|corporation)\b"#, options: .regularExpression) != nil }
        return organizationHints.first
    }

    private func extractAgreementObject(from text: String) -> String? {
        let lines = significantLines(from: text)
        for line in lines {
            let normalized = normalizedSearchText(line)
            if normalized.contains("entente") || normalized.contains("contrat") || normalized.contains("convention") || normalized.contains("bail") {
                let cleaned = stripAgreementFamilyLeadIn(line)
                if cleaned.count >= 8 {
                    return cleaned
                }
            }
        }
        return significantUppercaseLine(in: text)
    }

    private func extractAgreementPeriod(from text: String) -> String? {
        let normalized = normalizedSearchText(text)
        let years = extractYears(from: normalized)
        if normalized.contains("indeterminee") || normalized.contains("indéterminée") {
            if let start = years.min() {
                return "\(start)-Indéterminée"
            }
            return "Indéterminée"
        }
        guard !years.isEmpty else { return nil }
        if let minYear = years.min(), let maxYear = years.max() {
            return minYear == maxYear ? "\(minYear)" : "\(minYear)-\(maxYear)"
        }
        return nil
    }
}

private func normalizeDocumentNumber(_ value: String) -> String {
    FilenameGuardrails.normalizeFrenchTypography(value)
        .replacingOccurrences(of: #"\bNO\s+"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizeDateString(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
        return trimmed
    }

    let normalized = normalizedSearchText(trimmed)
    let parts = normalized.split(separator: " ").map(String.init)
    guard parts.count >= 3 else { return nil }
    guard let day = Int(parts[0]), let month = frenchMonthNumber(parts[1]), let year = Int(parts[2]) else {
        return nil
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
}

private func frenchMonthNumber(_ raw: String) -> Int? {
    switch normalizedSearchText(raw) {
    case "janvier": return 1
    case "fevrier": return 2
    case "mars": return 3
    case "avril": return 4
    case "mai": return 5
    case "juin": return 6
    case "juillet": return 7
    case "aout": return 8
    case "septembre": return 9
    case "octobre": return 10
    case "novembre": return 11
    case "decembre": return 12
    default: return nil
    }
}

private func buildAliasMap(_ thesaurus: NamingThesaurus?) -> [String: String] {
    guard let thesaurus else { return [:] }
    var result: [String: String] = [:]
    for entry in thesaurus.entries {
        let canonical = entry.normalized_output ?? entry.canonical
        result[normalizedSearchText(entry.canonical)] = canonical
        for alias in entry.aliases {
            result[normalizedSearchText(alias)] = canonical
        }
    }
    return result
}

private func canonicalizePhrase(_ value: String, aliasMap: [String: String]) -> String {
    let normalizedValue = normalizedSearchText(value)
    if let direct = aliasMap[normalizedValue] {
        return direct
    }
    var output = value
    for (alias, canonical) in aliasMap.sorted(by: { $0.key.count > $1.key.count }) {
        let pattern = #"\b\#(NSRegularExpression.escapedPattern(for: alias))\b"#
        output = output.replacingOccurrences(
            of: pattern,
            with: canonical,
            options: [.regularExpression, .caseInsensitive]
        )
    }
    return FilenameGuardrails.normalizeFrenchTypography(output)
}

private func cleanObjectPhrase(_ value: String, stopwords: Set<String>, preserve: Set<String>) -> String {
    let originalTokens = value
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" && $0 != "-" })
        .map(String.init)
    let kept = originalTokens.filter { token in
        let normalized = normalizedSearchText(token)
        if preserve.contains(normalized) {
            return true
        }
        return !stopwords.contains(normalized)
    }
    let output = kept.joined(separator: " ")
    return FilenameGuardrails.normalizeFrenchTypography(output)
}

private func stripAgreementFamilyLeadIn(_ value: String) -> String {
    let pattern = #"(?i)^\s*(entente|contrat|convention|bail|protocole|avenant)(?:\s+(?:pour|de|d'|relatif\s+a|relative\s+a|d'utilisation|de bon voisinage))?\s*"#
    let stripped = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    return FilenameGuardrails.normalizeFrenchTypography(stripped)
}

private func cleanupCounterparties(_ value: String) -> String {
    FilenameGuardrails.normalizeFrenchTypography(value)
        .replacingOccurrences(of: #"(?i)^(la\s+)?ville\s+d[' ]amos\s+(?:et|avec)\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?i)\s+(?:et|avec)\s+(la\s+)?ville\s+d[' ]amos$"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: " -–,.;:"))
}

private func normalizePeriod(_ value: String) -> String {
    let years = extractYears(from: normalizedSearchText(value))
    if value.localizedCaseInsensitiveContains("indétermin") || value.localizedCaseInsensitiveContains("indetermin") {
        if let minYear = years.min() {
            return "\(minYear)-Indéterminée"
        }
        return "Indéterminée"
    }
    guard !years.isEmpty else {
        return FilenameGuardrails.normalizeFrenchTypography(value)
    }
    if let minYear = years.min(), let maxYear = years.max() {
        return minYear == maxYear ? "\(minYear)" : "\(minYear)-\(maxYear)"
    }
    return FilenameGuardrails.normalizeFrenchTypography(value)
}

private func extractYears(from text: String) -> [Int] {
    let regex = try? NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex?.matches(in: text, range: range)
        .compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return Int(text[range])
        } ?? []
}

private func significantLines(from text: String) -> [String] {
    text
        .split(whereSeparator: \.isNewline)
        .map { FilenameGuardrails.normalizeFrenchTypography(String($0)) }
        .filter { $0.count >= 4 }
}

private func significantUppercaseLine(in text: String) -> String? {
    significantLines(from: text).first { line in
        let letters = line.filter(\.isLetter)
        guard letters.count >= 8 else { return false }
        let uppercaseCount = letters.filter(\.isUppercase).count
        return uppercaseCount >= max(4, letters.count / 2)
    }
}

private func firstMatch(pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
    guard let swiftRange = Range(captureRange, in: text) else { return nil }
    return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
}
