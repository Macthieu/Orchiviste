import Foundation

public enum FilenameGuardrails {
    public static let maxRecommendedLength = 256

    private static let technicalMentionPatterns: [String] = [
        #"(?i)\bpdf\s*/?\s*a(?:-\d+[a-z]?)?\b"#,
        #"(?i)\bocr\b"#,
        #"(?i)\bscan(?:ne|nee|nees|ner|ners|ned)?\b"#,
        #"(?i)\bscann(?:e|ee|ees|er|es)?\b"#,
        #"(?i)\bnumeris(?:e|ee|ees|er|es)?\b"#,
        #"(?i)\bsign(?:e|ee|ees|er|es)?\b"#,
        #"(?i)\bversion\s+finale\b"#,
        #"(?i)\bnon\s+sign[ée]e?\b"#
    ]

    public static func containsTechnicalMention(_ value: String) -> Bool {
        technicalMentionPatterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    public static func stripTechnicalMentions(_ value: String) -> String {
        var output = value
        for pattern in technicalMentionPatterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }
        return collapseWhitespace(output)
    }

    public static func collapseWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizeFrenchTypography(_ value: String) -> String {
        var output = stripTechnicalMentions(value)
        output = output.precomposedStringWithCanonicalMapping
        output = output.replacingOccurrences(
            of: #"\b[Nn](?:[°ºoO]|o\.)\s*"#,
            with: "NO ",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\s+[.](pdf|docx|xlsx|pptx|png|jpg|jpeg|tif|tiff)$"#,
            with: ".$1",
            options: [.regularExpression, .caseInsensitive]
        )
        output = output.replacingOccurrences(
            of: #"\s*[-–—]\s*"#,
            with: " – ",
            options: .regularExpression
        )
        return collapseWhitespace(output)
    }

    public static func normalizedStem(_ value: String) -> String {
        normalizeFrenchTypography(value)
    }

    public static func validateCandidateStem(_ value: String) -> String? {
        let normalized = normalizedStem(value)
        guard !normalized.isEmpty else {
            return "Le nom final ne peut pas être vide."
        }
        if containsTechnicalMention(normalized) {
            return "Le nom final ne doit pas contenir de mentions techniques."
        }
        if normalized.count > maxRecommendedLength {
            return "Le nom final dépasse \(maxRecommendedLength) caractères."
        }
        return nil
    }

    public static func truncateFileNameIfNeeded(_ value: String) -> String {
        guard value.count > maxRecommendedLength else {
            return value
        }

        let url = URL(fileURLWithPath: value)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let maxStemLength = max(1, maxRecommendedLength - suffix.count)
        let truncatedStem = String(stem.prefix(maxStemLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return truncatedStem + suffix
    }
}
