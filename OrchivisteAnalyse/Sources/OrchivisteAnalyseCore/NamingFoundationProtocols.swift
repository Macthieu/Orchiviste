import Foundation
import OrchivisteSharedKit

public protocol NamingRuleDetecting {
    func detectRule(
        in text: String,
        metadata: NamingSourceMetadata?,
        rules: [NamingRuleDefinition]
    ) -> NamingRuleDefinition?
}

public protocol NamingFieldExtracting {
    func extractFields(
        from text: String,
        rule: NamingRuleDefinition,
        metadata: NamingSourceMetadata?
    ) -> [String: String]
}

public protocol NamingFieldNormalizing {
    func normalizeFields(
        _ fields: [String: String],
        rule: NamingRuleDefinition,
        thesaurus: NamingThesaurus?
    ) -> [String: String]
}

public protocol NamingFileRendering {
    func renderFilename(
        rule: NamingRuleDefinition,
        fields: [String: String]
    ) -> String
}

public protocol NamingFileValidating {
    func validateFilename(
        _ filename: String,
        rule: NamingRuleDefinition,
        fields: [String: String]
    ) -> [NamingRuleValidationIssue]
}

public protocol ThesaurusImporting {
    var format: String { get }
    func parse(data: Data, sourceName: String?) throws -> NamingThesaurus
}

public protocol RuleLearning {
    func learn(
        request: RuleLearningRequest,
        samples: [LearningDocumentSample],
        baseThesaurus: NamingThesaurus
    ) -> NamingRuleDraft
}
