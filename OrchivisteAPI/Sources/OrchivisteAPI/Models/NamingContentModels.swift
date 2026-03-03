import OrchivisteSharedKit
import Vapor

extension NamingRuleDefinition: @retroactive Content {}
extension NamingRuleValidationRequest: @retroactive Content {}
extension NamingRuleValidationResult: @retroactive Content {}
extension RuleLearningRequest: @retroactive Content {}
extension NamingRuleDraft: @retroactive Content {}
extension NamingDraftIndex: @retroactive Content {}
extension NamingThesaurus: @retroactive Content {}
extension ThesaurusImportPreviewRequest: @retroactive Content {}
extension ThesaurusImportConfirmRequest: @retroactive Content {}
extension ImportedThesaurusDraft: @retroactive Content {}
