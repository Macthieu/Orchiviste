import Foundation

struct IDPSegmentation: Sendable {
    let unitCount: Int
    let sectionTitles: [String]
    let boundaryMarkers: [String]
}

struct IDPReviewAssessment: Sendable {
    let needsReview: Bool
    let reasons: [String]
    let missingFields: [String]
    let ambiguousFields: [String]
}

struct IDPPipelineOutput: Sendable {
    let relevantPages: [Int]
    let hasTableLayout: Bool
    let titleHints: [String]
    let clauseAttenduQueCount: Int
    let clauseResoluCount: Int
    let semanticFields: [String: String]
    let fieldSources: [String: AnalysisFieldSource]
    let validationFlags: [String]
    let completenessScore: Double
    let captureStrategy: String
    let segmentation: IDPSegmentation
    let warnings: [String]
    let review: IDPReviewAssessment
}

private struct ExtractedSemanticFields {
    var fields: [String: String] = [:]
    var fieldSources: [String: AnalysisFieldSource] = [:]
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
        let sectionTitles = detectSectionTitles(rawText: rawText, titleHints: titleHints)
        let segmentation = detectSegmentation(
            rawText: rawText,
            typeDoc: typeDoc,
            titleHints: titleHints,
            sectionTitles: sectionTitles
        )
        let clauseAttenduQueCount = countMatches(
            in: normalizedAll,
            pattern: #"\battendu\s+que\b"#
        )
        let clauseResoluCount = countMatches(
            in: normalizedAll,
            pattern: #"\bil\s+est\s+resolu\b"#
        )
        let extracted = extractSemanticFields(rawText: rawText, typeDoc: typeDoc)
        let validation = validate(
            typeDoc: typeDoc,
            baseFields: baseFields,
            semanticFields: extracted.fields,
            clauseResoluCount: clauseResoluCount
        )
        let ambiguousFields = detectAmbiguousFields(
            rawText: rawText,
            typeDoc: typeDoc,
            baseFields: baseFields,
            semanticFields: extracted.fields,
            segmentation: segmentation
        )
        let captureStrategy = detectCaptureStrategy(request: request, rawText: rawText)
        let warnings = buildWarnings(
            captureStrategy: captureStrategy,
            segmentation: segmentation,
            ambiguousFields: ambiguousFields,
            completeness: validation.completeness
        )
        let missingFields: [String] = validation.flags.compactMap { flag -> String? in
            guard flag.hasPrefix("missing_") else { return nil }
            return String(flag.dropFirst("missing_".count))
        }
        let review = buildReviewAssessment(
            captureStrategy: captureStrategy,
            segmentation: segmentation,
            missingFields: missingFields,
            ambiguousFields: ambiguousFields
        )
        let metadata = buildSuggestedMetadata(
            rawText: rawText,
            typeDoc: typeDoc,
            baseFields: baseFields,
            semanticFields: extracted.fields
        )
        let summary = buildGeneratedSummary(
            typeDoc: typeDoc,
            metadata: metadata,
            sujets: inferSummarySubjects(baseFields: baseFields, semanticFields: extracted.fields),
            review: review
        )

        var fields = extracted.fields
        fields["idp_pages_pertinentes"] = relevantPages.map(String.init).joined(separator: ",")
        fields["idp_layout_has_table"] = hasTableLayout ? "true" : "false"
        fields["idp_titles"] = titleHints.joined(separator: " | ")
        fields["idp_section_titles"] = segmentation.sectionTitles.joined(separator: " | ")
        fields["idp_boundary_markers"] = segmentation.boundaryMarkers.joined(separator: " | ")
        fields["idp_unit_count"] = "\(segmentation.unitCount)"
        fields["idp_clause_attendu_que_count"] = "\(clauseAttenduQueCount)"
        fields["idp_clause_resolu_count"] = "\(clauseResoluCount)"
        fields["idp_validation_completude"] = String(format: "%.2f", validation.completeness)
        fields["idp_validation_flags"] = validation.flags.joined(separator: ";")
        fields["idp_capture_strategy"] = captureStrategy
        fields["idp_review_needs_review"] = review.needsReview ? "true" : "false"
        fields["idp_review_reasons"] = review.reasons.joined(separator: ";")
        fields["idp_review_missing_fields"] = review.missingFields.joined(separator: ";")
        fields["idp_review_ambiguous_fields"] = review.ambiguousFields.joined(separator: ";")
        fields["idp_warnings"] = warnings.joined(separator: ";")
        fields["summary.title"] = summary.title
        fields["summary.generated"] = summary.text
        fields["summary.highlights"] = summary.highlights.joined(separator: " | ")
        fields["idp_field_sources"] = extracted.fieldSources
            .keys
            .sorted()
            .compactMap { key in
                guard let source = extracted.fieldSources[key] else { return nil }
                return "\(key):\(source.source)"
            }
            .joined(separator: ";")
        fields["idp_action"] = suggestedAction(
            totalPages: pages.count,
            relevantPages: relevantPages,
            typeDoc: typeDoc,
            segmentation: segmentation,
            review: review
        )
        for (key, value) in metadata {
            fields["metadata.\(key)"] = value
        }

        return IDPPipelineOutput(
            relevantPages: relevantPages,
            hasTableLayout: hasTableLayout,
            titleHints: titleHints,
            clauseAttenduQueCount: clauseAttenduQueCount,
            clauseResoluCount: clauseResoluCount,
            semanticFields: fields,
            fieldSources: extracted.fieldSources,
            validationFlags: validation.flags,
            completenessScore: validation.completeness,
            captureStrategy: captureStrategy,
            segmentation: segmentation,
            warnings: warnings,
            review: review
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

    private static func cleanedLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                guard !$0.isEmpty else { return false }
                return !matches($0, pattern: #"(?i)^\s*(file_name|tags)\s*:"#)
            }
    }

    private static func detectCaptureStrategy(
        request: AnalysisRequest,
        rawText: String
    ) -> String {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "no_text_semantic"
        }

        let sourceKind = request.source?.kind?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if sourceKind.contains("scan") || sourceKind.contains("image") || sourceKind.contains("ocr") {
            return "ocr_semantic_assisted"
        }

        let lines = cleanedLines(from: rawText)
        guard !lines.isEmpty else {
            return "native_text_semantic"
        }

        let shortLines = lines.filter { $0.count <= 28 }.count
        let compactLines = lines.filter { $0.split(whereSeparator: \.isWhitespace).count <= 2 }.count
        let shortRatio = Double(shortLines) / Double(lines.count)
        let compactRatio = Double(compactLines) / Double(lines.count)

        if lines.count >= 20 && shortRatio >= 0.45 && compactRatio >= 0.30 {
            return "ocr_semantic_assisted"
        }
        return "native_text_semantic"
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
            tokens = ["signature", "date", "numero", "contrat", "bail"]
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
        let lines = cleanedLines(from: rawText)
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
        let lines = cleanedLines(from: rawText).prefix(25)

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

    private static func detectSectionTitles(
        rawText: String,
        titleHints: [String]
    ) -> [String] {
        let patterns = [
            #"(?im)^\s*(?:objet|subject)\s*[:\-]?\s*.+$"#,
            #"(?im)^\s*(?:attendu\s+que|considerant|considérant)\b.*$"#,
            #"(?im)^\s*(?:il\s+est\s+resolu|il\s+est\s+r[eé]solu)\b.*$"#,
            #"(?im)^\s*(?:article|section)\s+\d+[^\n\r]*$"#,
            #"(?im)^\s*(?:annexe|appendice|signature|extrait certifie conforme)\b.*$"#
        ]

        var titles = orderedUnique(titleHints)
        for line in cleanedLines(from: rawText) {
            guard line.count <= 160 else { continue }
            if patterns.contains(where: { matches(line, pattern: $0) }) {
                titles.append(line)
            }
            if titles.count >= 8 {
                break
            }
        }
        return orderedUnique(titles).prefixing(8)
    }

    private static func detectSegmentation(
        rawText: String,
        typeDoc: String,
        titleHints: [String],
        sectionTitles: [String]
    ) -> IDPSegmentation {
        let markerPatterns: [String]
        switch typeDoc {
        case "Resolution":
            markerPatterns = [
                #"(?i)^\s*(?:r[eé]solution)\b.*(?:n[°o]?|#|no)?\s*[a-z]?\d"#,
                #"(?i)^\s*extrait\s+du\s+proc[eè]s[- ]verbal\b.*$"#
            ]
        case "Facture":
            markerPatterns = [
                #"(?i)^\s*(?:facture|invoice)\b.*(?:n[°o]?|#|no)?\s*[a-z]?\d"#,
                #"(?i)^\s*(?:bon\s+de\s+commande)\b.*$"#
            ]
        case "ProcesVerbal":
            markerPatterns = [
                #"(?i)^\s*(?:proc[eè]s[- ]verbal|proces[- ]verbal)\b.*$"#
            ]
        default:
            markerPatterns = [
                #"(?i)^\s*(?:contrat|bail|entente|rapport)\b.*$"#
            ]
        }

        var boundaryMarkers: [String] = []
        for line in cleanedLines(from: rawText) {
            if markerPatterns.contains(where: { matches(line, pattern: $0) }) {
                boundaryMarkers.append(line)
            }
            if boundaryMarkers.count >= 6 {
                break
            }
        }

        let uniqueMarkers = orderedUnique(boundaryMarkers)
        let inferredUnits = max(1, uniqueMarkers.count)
        let combinedSections = orderedUnique(titleHints + sectionTitles)
        return IDPSegmentation(
            unitCount: inferredUnits,
            sectionTitles: combinedSections.prefixing(8),
            boundaryMarkers: uniqueMarkers.prefixing(4)
        )
    }

    private static func extractSemanticFields(
        rawText: String,
        typeDoc: String
    ) -> ExtractedSemanticFields {
        var extracted = ExtractedSemanticFields()

        assignFirstMatch(
            key: "montant_total",
            pattern: #"(?i)\b(?:montant(?:\s+total)?|total)\s*[:\-]?\s*([$€]?\s?[0-9]{1,3}(?:[ \u00A0.,][0-9]{3})*(?:[.,][0-9]{2})?)\b"#,
            source: "regex_total_amount",
            rawText: rawText,
            confidence: 0.83,
            into: &extracted
        )
        assignFirstMatch(
            key: "resolution_titre",
            pattern: #"(?im)^\s*(r[eé]solution[^\n\r]{0,120})$"#,
            source: "regex_resolution_title",
            rawText: rawText,
            confidence: 0.79,
            into: &extracted
        )
        assignFirstMatch(
            key: "resolution_numero",
            pattern: #"(?i)\b(?:r[eé]s(?:olution)?)\s*[:#\-]?\s*([0-9]{2,4}(?:[-/][0-9]{1,4})?)\b"#,
            source: "regex_resolution_number",
            rawText: rawText,
            confidence: 0.85,
            into: &extracted
        )
        assignFirstMatch(
            key: "date_document",
            pattern: #"(?i)\b(?:20\d{2}[-/]\d{2}[-/]\d{2}|\d{4}-\d{2}-\d{2}|[0-3]?\d\s+(?:janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre)\s+20\d{2})\b"#,
            source: "regex_document_date",
            rawText: rawText,
            confidence: 0.78,
            into: &extracted
        )
        assignFirstMatch(
            key: "document_objet",
            pattern: #"(?im)^\s*(?:objet|subject)\s*[:\-]?\s*(.{4,120})$"#,
            source: "regex_document_subject",
            rawText: rawText,
            confidence: 0.74,
            into: &extracted
        )
        assignFirstMatch(
            key: "organisme_emetteur",
            pattern: #"(?im)^\s*((?:ville|municipalite|municipalité|communaute|communauté|mrc|conseil)[^\n\r]{0,120})$"#,
            source: "regex_issuer_heading",
            rawText: rawText,
            confidence: 0.72,
            into: &extracted
        )
        if extracted.fields["document_objet"] == nil,
           let derivedObject = inferDocumentObject(rawText: rawText, typeDoc: typeDoc) {
            extracted.fields["document_objet"] = derivedObject
            extracted.fieldSources["document_objet"] = AnalysisFieldSource(
                source: "semantic_heading_object",
                confidence: 0.68,
                evidence: clippedEvidence(derivedObject)
            )
        }

        if extracted.fields["doc_type_hint"] == nil {
            extracted.fields["doc_type_hint"] = typeDoc
            extracted.fieldSources["doc_type_hint"] = AnalysisFieldSource(
                source: "semantic_type_inference",
                confidence: 0.65,
                evidence: typeDoc
            )
        }

        return extracted
    }

    private static func validate(
        typeDoc: String,
        baseFields: [String: String],
        semanticFields: [String: String],
        clauseResoluCount: Int
    ) -> (flags: [String], completeness: Double) {
        var flags: [String] = []
        let requiredChecks: [(String, Bool)]

        switch typeDoc {
        case "Facture":
            requiredChecks = [
                ("numero", nonEmpty(baseFields["numero"]) != nil),
                ("date", nonEmpty(baseFields["date"]) != nil || nonEmpty(semanticFields["date_document"]) != nil),
                ("montant_total", nonEmpty(semanticFields["montant_total"]) != nil)
            ]
        case "Resolution":
            requiredChecks = [
                ("date", nonEmpty(baseFields["date"]) != nil || nonEmpty(semanticFields["date_document"]) != nil),
                ("numero", nonEmpty(baseFields["numero"]) != nil || nonEmpty(semanticFields["resolution_numero"]) != nil),
                ("clause_resolu", clauseResoluCount > 0)
            ]
        case "ProcesVerbal":
            requiredChecks = [
                ("date", nonEmpty(baseFields["date"]) != nil || nonEmpty(semanticFields["date_document"]) != nil),
                ("comite", nonEmpty(baseFields["comite"]) != nil || nonEmpty(semanticFields["organisme_emetteur"]) != nil)
            ]
        default:
            requiredChecks = [
                ("date_or_numero", nonEmpty(baseFields["date"]) != nil || nonEmpty(baseFields["numero"]) != nil || nonEmpty(semanticFields["date_document"]) != nil)
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

        let completeness = requiredChecks.isEmpty
            ? 1.0
            : Double(passed) / Double(requiredChecks.count)
        return (flags, completeness)
    }

    private static func detectAmbiguousFields(
        rawText: String,
        typeDoc: String,
        baseFields: [String: String],
        semanticFields: [String: String],
        segmentation: IDPSegmentation
    ) -> [String] {
        var ambiguous: [String] = []

        let dateMatches = distinctMatches(
            in: rawText,
            pattern: #"(?i)\b(?:20\d{2}[-/]\d{2}[-/]\d{2}|\d{4}-\d{2}-\d{2}|[0-3]?\d\s+(?:janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre)\s+20\d{2})\b"#
        )
        if dateMatches.count > 1,
           nonEmpty(baseFields["date"]) == nil,
           nonEmpty(semanticFields["date_document"]) == nil {
            ambiguous.append("date")
        }

        let numberPattern: String
        switch typeDoc {
        case "Resolution":
            numberPattern = #"(?i)\b(?:r[eé]s(?:olution)?)\s*[:#\-]?\s*([0-9]{2,4}(?:[-/][0-9]{1,4})?)\b"#
        case "Facture":
            numberPattern = #"(?i)\b(?:facture|invoice)\s*(?:n[°o]?|#|no)?\s*([a-z0-9][a-z0-9\-\/]{2,})\b"#
        default:
            numberPattern = #"(?i)\b(?:pv|res|r|fac|facture)[-\s]?\d{2,4}(?:[-/]\d+)?\b"#
        }
        if distinctMatches(in: rawText, pattern: numberPattern).count > 1,
           nonEmpty(baseFields["numero"]) == nil,
           nonEmpty(semanticFields["resolution_numero"]) == nil {
            ambiguous.append("numero")
        }

        if typeDoc == "Facture",
           distinctMatches(
                in: rawText,
                pattern: #"(?i)\b(?:montant(?:\s+total)?|total)\s*[:\-]?\s*([$€]?\s?[0-9]{1,3}(?:[ \u00A0.,][0-9]{3})*(?:[.,][0-9]{2})?)\b"#
           ).count > 1,
           nonEmpty(semanticFields["montant_total"]) == nil {
            ambiguous.append("montant_total")
        }

        if distinctMatches(
            in: rawText,
            pattern: #"(?im)^\s*(?:comite|comité|committee)\s*[:\-]?\s*([^\n\r,;.]+)"#
        ).count > 1,
           nonEmpty(baseFields["comite"]) == nil {
            ambiguous.append("comite")
        }

        if segmentation.unitCount > 1 {
            ambiguous.append("document_units")
        }

        return orderedUnique(ambiguous)
    }

    private static func buildWarnings(
        captureStrategy: String,
        segmentation: IDPSegmentation,
        ambiguousFields: [String],
        completeness: Double
    ) -> [String] {
        var warnings: [String] = []
        if captureStrategy == "ocr_semantic_assisted" {
            warnings.append("ocr_like_text_detected")
        }
        if segmentation.unitCount > 1 {
            warnings.append("multi_document_units_detected")
        }
        if !ambiguousFields.isEmpty {
            warnings.append("ambiguous_fields_detected")
        }
        if completeness < 0.5 {
            warnings.append("low_completeness_detected")
        }
        return warnings
    }

    private static func buildReviewAssessment(
        captureStrategy: String,
        segmentation: IDPSegmentation,
        missingFields: [String],
        ambiguousFields: [String]
    ) -> IDPReviewAssessment {
        var reasons: [String] = []
        if !missingFields.isEmpty {
            reasons.append("missing_required_fields")
        }
        if !ambiguousFields.isEmpty {
            reasons.append("ambiguous_fields")
        }
        if segmentation.unitCount > 1 {
            reasons.append("multi_document_units")
        }
        if captureStrategy == "ocr_semantic_assisted" && !missingFields.isEmpty {
            reasons.append("ocr_sensitive_review")
        }
        return IDPReviewAssessment(
            needsReview: !reasons.isEmpty,
            reasons: orderedUnique(reasons),
            missingFields: orderedUnique(missingFields),
            ambiguousFields: orderedUnique(ambiguousFields)
        )
    }

    private static func suggestedAction(
        totalPages: Int,
        relevantPages: [Int],
        typeDoc: String,
        segmentation: IDPSegmentation,
        review: IDPReviewAssessment
    ) -> String {
        if segmentation.unitCount > 1 {
            return "segmenter_unites_documentaires"
        }
        if review.needsReview {
            return "reviser_avant_routage"
        }
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

    private static func assignFirstMatch(
        key: String,
        pattern: String,
        source: String,
        rawText: String,
        confidence: Double,
        into extracted: inout ExtractedSemanticFields
    ) {
        guard let value = firstMatch(in: rawText, pattern: pattern) else {
            return
        }
        extracted.fields[key] = value
        extracted.fieldSources[key] = AnalysisFieldSource(
            source: source,
            confidence: confidence,
            evidence: clippedEvidence(value)
        )
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
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

    private static func distinctMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var values: [String] = []
        for match in matches {
            let targetRange: NSRange
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                targetRange = match.range(at: 1)
            } else {
                targetRange = match.range
            }
            guard let swiftRange = Range(targetRange, in: text) else {
                continue
            }
            values.append(String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return orderedUnique(values)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private static func clippedEvidence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 120 {
            return trimmed
        }
        return String(trimmed.prefix(120))
    }

    private static func inferDocumentObject(rawText: String, typeDoc: String) -> String? {
        let lines = cleanedLines(from: rawText)
        guard !lines.isEmpty else { return nil }

        if typeDoc == "Resolution" {
            for (index, line) in lines.enumerated() {
                if matches(line, pattern: #"(?i)\br[eé]solution\b"#) {
                    let window = lines.dropFirst(index + 1).prefix(4)
                    let candidates = window.filter { candidate in
                        candidate.count >= 18 && candidate.count <= 180
                    }
                    if !candidates.isEmpty {
                        let joined = candidates
                            .prefix(2)
                            .joined(separator: " ")
                            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let joined = sanitizedSemanticDisplayValue(joined) {
                            return joined
                        }
                    }
                }
            }
        }

        return lines
            .first(where: { line in
                line.count >= 18 &&
                line.count <= 160 &&
                !matches(line, pattern: #"(?i)^\s*(ville|municipalite|municipalité|mrc|conseil)\b"#) &&
                !matches(line, pattern: #"(?i)^\s*(r[eé]solution|proc[eè]s[- ]verbal|facture)\b"#)
            })
            .flatMap(sanitizedSemanticDisplayValue)
    }

    private static func buildSuggestedMetadata(
        rawText: String,
        typeDoc: String,
        baseFields: [String: String],
        semanticFields: [String: String]
    ) -> [String: String] {
        let number = sanitizedSemanticDisplayValue(nonEmpty(semanticFields["resolution_numero"]))
            ?? sanitizedSemanticDisplayValue(nonEmpty(baseFields["numero"]))
        let object = sanitizedSemanticDisplayValue(nonEmpty(semanticFields["document_objet"]))
            ?? sanitizedSemanticDisplayValue(nonEmpty(semanticFields["resolution_titre"]))
        let date = nonEmpty(baseFields["date"])
            ?? nonEmpty(semanticFields["date_document"])
        let issuer = sanitizedSemanticDisplayValue(nonEmpty(semanticFields["organisme_emetteur"]))
            ?? sanitizedSemanticDisplayValue(nonEmpty(baseFields["comite"]))
        let keywords = orderedUnique(cleanedLines(from: rawText).prefix(12).flatMap { line in
            line
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { token in
                    token.count >= 5 && !token.allSatisfy(\.isNumber)
                }
        }).prefixing(5)

        var metadata: [String: String] = [
            "type_document": typeDoc
        ]
        if let number { metadata["numero_document"] = number }
        if let object { metadata["objet"] = object }
        if let date { metadata["date_document"] = date }
        if let issuer { metadata["organisme_emetteur"] = issuer }
        if !keywords.isEmpty {
            metadata["mots_cles"] = keywords.joined(separator: ", ")
        }
        return metadata
    }

    private static func inferSummarySubjects(
        baseFields: [String: String],
        semanticFields: [String: String]
    ) -> [String] {
        let values = [
            sanitizedSemanticDisplayValue(nonEmpty(baseFields["comite"])),
            sanitizedSemanticDisplayValue(nonEmpty(semanticFields["organisme_emetteur"])),
            sanitizedSemanticDisplayValue(nonEmpty(semanticFields["document_objet"]))
        ].compactMap { $0 }
        return orderedUnique(values).prefixing(3)
    }

    private static func buildGeneratedSummary(
        typeDoc: String,
        metadata: [String: String],
        sujets: [String],
        review: IDPReviewAssessment
    ) -> (title: String, text: String, highlights: [String]) {
        let title = nonEmpty(metadata["objet"])
            ?? nonEmpty(metadata["numero_document"])
            ?? nonEmpty(typeDoc)
            ?? "Document"
        let number = nonEmpty(metadata["numero_document"])
        let date = nonEmpty(metadata["date_document"])
        let issuer = nonEmpty(metadata["organisme_emetteur"])

        var firstSentence = typeDoc
        if let number {
            firstSentence += " \(number)"
        }
        if let issuer {
            firstSentence += " émis par \(issuer)"
        }
        if let date {
            firstSentence += " daté du \(date)"
        }
        firstSentence += "."

        var summaryParts = [firstSentence]
        if let object = nonEmpty(metadata["objet"]) {
            summaryParts.append("Objet suggéré: \(object).")
        }
        if !sujets.isEmpty {
            summaryParts.append("Axes détectés: \(sujets.joined(separator: ", ")).")
        }
        if review.needsReview {
            summaryParts.append("Une revue humaine est recommandée avant le routage.")
        }

        var highlights: [String] = []
        if let number {
            highlights.append("Numéro: \(number)")
        }
        if let object = nonEmpty(metadata["objet"]) {
            highlights.append("Objet: \(object)")
        }
        if let date {
            highlights.append("Date: \(date)")
        }
        if let issuer {
            highlights.append("Émetteur: \(issuer)")
        }
        return (
            title: title,
            text: summaryParts.joined(separator: " "),
            highlights: orderedUnique(highlights).prefixing(4)
        )
    }

    private static func sanitizedSemanticDisplayValue(_ raw: String?) -> String? {
        guard let value = nonEmpty(raw) else {
            return nil
        }
        let compacted = value
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compacted.isEmpty else {
            return nil
        }
        guard !matches(compacted, pattern: #"(?i)^\s*(file_name|tags)\s*:"#) else {
            return nil
        }
        guard !looksLikeStructuredHeaderNoise(compacted) else {
            return nil
        }
        return compacted
    }

    private static func looksLikeStructuredHeaderNoise(_ value: String) -> Bool {
        let lowered = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let invoiceHeaderTokens = [
            "titulaire du compte",
            "numero de compte",
            "date de facturation",
            "numero du client",
            "numero client",
            "page"
        ]
        let invoiceHeaderHits = invoiceHeaderTokens.filter { lowered.contains($0) }.count
        if invoiceHeaderHits >= 3 {
            return true
        }

        if value.range(of: #"\S+\s{4,}\S+\s{4,}\S+"#, options: .regularExpression) != nil,
           lowered.contains("numero") || lowered.contains("date") || lowered.contains("page") {
            return true
        }
        return false
    }
}

private extension Array where Element == String {
    func prefixing(_ maxCount: Int) -> [String] {
        let bounded = maxCount > 0 ? maxCount : 0
        return Array(prefix(bounded))
    }
}
