import Foundation
import OrchivisteSharedKit

enum NamingPolicy {
    static let maxRecommendedLength = FilenameGuardrails.maxRecommendedLength

    static func containsTechnicalMention(_ value: String) -> Bool {
        FilenameGuardrails.containsTechnicalMention(value)
    }

    static func stripTechnicalMentions(_ value: String) -> String {
        FilenameGuardrails.stripTechnicalMentions(value)
    }

    static func normalizedStem(_ value: String) -> String {
        FilenameGuardrails.normalizedStem(value)
    }

    static func validateCandidateStem(_ value: String) -> String? {
        FilenameGuardrails.validateCandidateStem(value)
    }

    static func truncateFileNameIfNeeded(_ value: String) -> String {
        FilenameGuardrails.truncateFileNameIfNeeded(value)
    }
}
