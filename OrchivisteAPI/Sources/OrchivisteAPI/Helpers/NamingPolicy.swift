import Foundation

enum NamingPolicy {
    static let maxRecommendedLength = 256

    private static let technicalMentionPatterns: [String] = [
        #"(?i)\bpdf\s*/?\s*a(?:-\d+[a-z]?)?\b"#,
        #"(?i)\bocr\b"#,
        #"(?i)\bscan(?:ne|nee|nees|nees|ner|ners|ned)?\b"#,
        #"(?i)\bscann(?:e|ee|ees|er|es)?\b"#,
        #"(?i)\bnumeris(?:e|ee|ees|er|es)?\b"#,
        #"(?i)\bsign(?:e|ee|ees|er|es)?\b"#
    ]

    static func containsTechnicalMention(_ value: String) -> Bool {
        technicalMentionPatterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func stripTechnicalMentions(_ value: String) -> String {
        var output = value
        for pattern in technicalMentionPatterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }
        output = output.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\s*-\s*-\s*"#,
            with: "-",
            options: .regularExpression
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedStem(_ value: String) -> String {
        let stripped = stripTechnicalMentions(value)
        let collapsed = stripped.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validateCandidateStem(_ value: String) -> String? {
        let normalized = normalizedStem(value)
        guard !normalized.isEmpty else {
            return "Le nom final ne peut pas etre vide."
        }
        if containsTechnicalMention(normalized) {
            return "Le nom final ne doit pas contenir de mentions techniques."
        }
        if normalized.count > maxRecommendedLength {
            return "Le nom final depasse \(maxRecommendedLength) caracteres."
        }
        return nil
    }

    static func truncateFileNameIfNeeded(_ value: String) -> String {
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
