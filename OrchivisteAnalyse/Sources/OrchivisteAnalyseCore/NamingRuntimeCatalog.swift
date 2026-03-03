import Foundation
import OrchivisteSharedKit

public enum NamingArtifactStatus: String, Codable, CaseIterable, Sendable {
    case active
    case draft
    case archived
    case fallback
}

public enum NamingArtifactSourceKind: String, Codable, CaseIterable, Sendable {
    case configFile
    case draftFile
    case archiveFile
    case fallbackSeed
    case imported
    case feedback
    case memory
}

public struct LoadedNamingRule: Codable, Sendable {
    public let rule_id: String
    public let version: String
    public let status: NamingArtifactStatus
    public let source: NamingArtifactSourceKind
    public let loaded_from: String?
    public let is_fallback: Bool
    public let updated_at: Date?
    public let definition: NamingRuleDefinition

    public init(
        rule_id: String,
        version: String,
        status: NamingArtifactStatus,
        source: NamingArtifactSourceKind,
        loaded_from: String? = nil,
        is_fallback: Bool = false,
        updated_at: Date? = nil,
        definition: NamingRuleDefinition
    ) {
        self.rule_id = rule_id
        self.version = version
        self.status = status
        self.source = source
        self.loaded_from = loaded_from
        self.is_fallback = is_fallback
        self.updated_at = updated_at
        self.definition = definition
    }
}

public struct LoadedNamingThesaurus: Codable, Sendable {
    public let thesaurus_id: String
    public let version: String
    public let status: NamingArtifactStatus
    public let source: NamingArtifactSourceKind
    public let loaded_from: String?
    public let is_fallback: Bool
    public let updated_at: Date?
    public let definition: NamingThesaurus

    public init(
        thesaurus_id: String,
        version: String,
        status: NamingArtifactStatus,
        source: NamingArtifactSourceKind,
        loaded_from: String? = nil,
        is_fallback: Bool = false,
        updated_at: Date? = nil,
        definition: NamingThesaurus
    ) {
        self.thesaurus_id = thesaurus_id
        self.version = version
        self.status = status
        self.source = source
        self.loaded_from = loaded_from
        self.is_fallback = is_fallback
        self.updated_at = updated_at
        self.definition = definition
    }
}

public struct PersistedNamingFeedback: Codable, Sendable {
    public let feedback_id: String
    public let rule_id: String
    public let created_at: Date
    public let source: NamingArtifactSourceKind
    public let feedback: NamingFeedbackExample

    public init(
        feedback_id: String,
        rule_id: String,
        created_at: Date,
        source: NamingArtifactSourceKind,
        feedback: NamingFeedbackExample
    ) {
        self.feedback_id = feedback_id
        self.rule_id = rule_id
        self.created_at = created_at
        self.source = source
        self.feedback = feedback
    }
}

public struct NamingRuntimeCatalog: Codable, Sendable {
    public let active_rules: [LoadedNamingRule]
    public let draft_rule_records: [LoadedNamingRule]
    public let archived_rules: [LoadedNamingRule]
    public let active_thesauri: [LoadedNamingThesaurus]
    public let archived_thesauri: [LoadedNamingThesaurus]
    public let rule_drafts: [NamingRuleDraft]
    public let thesaurus_drafts: [ImportedThesaurusDraft]
    public let feedback_records: [PersistedNamingFeedback]
    public let fallback_active: Bool

    public init(
        active_rules: [LoadedNamingRule],
        draft_rule_records: [LoadedNamingRule] = [],
        archived_rules: [LoadedNamingRule] = [],
        active_thesauri: [LoadedNamingThesaurus],
        archived_thesauri: [LoadedNamingThesaurus] = [],
        rule_drafts: [NamingRuleDraft] = [],
        thesaurus_drafts: [ImportedThesaurusDraft] = [],
        feedback_records: [PersistedNamingFeedback] = [],
        fallback_active: Bool = false
    ) {
        self.active_rules = active_rules
        self.draft_rule_records = draft_rule_records
        self.archived_rules = archived_rules
        self.active_thesauri = active_thesauri
        self.archived_thesauri = archived_thesauri
        self.rule_drafts = rule_drafts
        self.thesaurus_drafts = thesaurus_drafts
        self.feedback_records = feedback_records
        self.fallback_active = fallback_active
    }

    public func activeRuleDefinitions() -> [NamingRuleDefinition] {
        active_rules.map(\.definition)
    }

    public func primaryThesaurus() -> NamingThesaurus? {
        active_thesauri.first?.definition
    }

    public func ruleRecord(id: String, includeDrafts: Bool = true) -> LoadedNamingRule? {
        if let active = active_rules.first(where: { $0.rule_id == id }) {
            return active
        }
        if includeDrafts, let draft = draft_rule_records.first(where: { $0.rule_id == id }) {
            return draft
        }
        return archived_rules.first(where: { $0.rule_id == id })
    }

    public static func fallback(
        rules: [NamingRuleDefinition] = NamingFoundationSeeds.bootstrapFallbackRules(),
        thesaurus: NamingThesaurus = NamingFoundationSeeds.bootstrapFallbackThesaurus()
    ) -> NamingRuntimeCatalog {
        NamingRuntimeCatalog(
            active_rules: rules.map {
                LoadedNamingRule(
                    rule_id: $0.id,
                    version: $0.version,
                    status: .fallback,
                    source: .fallbackSeed,
                    loaded_from: nil,
                    is_fallback: true,
                    updated_at: nil,
                    definition: $0
                )
            },
            active_thesauri: [
                LoadedNamingThesaurus(
                    thesaurus_id: thesaurus.thesaurus_id,
                    version: thesaurus.version,
                    status: .fallback,
                    source: .fallbackSeed,
                    loaded_from: nil,
                    is_fallback: true,
                    updated_at: nil,
                    definition: thesaurus
                )
            ],
            fallback_active: true
        )
    }
}

public protocol NamingArtifactLocator {
    var namingBaseDirectory: URL { get }
    var rulesDirectory: URL { get }
    var thesaurusDirectory: URL { get }
    var ruleDraftsDirectory: URL { get }
    var thesaurusDraftsDirectory: URL { get }
    var archivedRulesDirectory: URL { get }
    var archivedThesauriDirectory: URL { get }
    var feedbackDirectory: URL { get }
}

public protocol NamingRuleRepository {
    func listActiveRules() throws -> [LoadedNamingRule]
    func listDraftRules() throws -> [LoadedNamingRule]
    func listArchivedRules() throws -> [LoadedNamingRule]
    func loadRule(id: String, includeDrafts: Bool) throws -> LoadedNamingRule?
    @discardableResult
    func saveRule(_ rule: NamingRuleDefinition, filename: String?) throws -> LoadedNamingRule
}

public protocol NamingThesaurusRepository {
    func listActiveThesauri() throws -> [LoadedNamingThesaurus]
    func listArchivedThesauri() throws -> [LoadedNamingThesaurus]
    func loadThesaurus(id: String) throws -> LoadedNamingThesaurus?
    @discardableResult
    func saveThesaurus(_ thesaurus: NamingThesaurus, filename: String?) throws -> LoadedNamingThesaurus
}

public protocol NamingDraftStore {
    func listRuleDrafts() throws -> [NamingRuleDraft]
    func listThesaurusDrafts() throws -> [ImportedThesaurusDraft]
    func loadThesaurusDraft(id: String) throws -> ImportedThesaurusDraft?
    @discardableResult
    func saveRuleDraft(_ draft: NamingRuleDraft) throws -> URL
    @discardableResult
    func saveThesaurusDraft(_ draft: ImportedThesaurusDraft) throws -> URL
}

public protocol NamingFeedbackStore {
    func listFeedback(ruleID: String?) throws -> [PersistedNamingFeedback]
    @discardableResult
    func recordFeedback(_ feedback: PersistedNamingFeedback) throws -> URL
}

public protocol NamingPersistenceStore: NamingRuleRepository, NamingThesaurusRepository, NamingDraftStore, NamingFeedbackStore {
    func loadRuntimeCatalog() throws -> NamingRuntimeCatalog
}

public final class InMemoryNamingStore: NamingPersistenceStore {
    private var activeRules: [LoadedNamingRule]
    private var archivedRules: [LoadedNamingRule]
    private var activeThesauri: [LoadedNamingThesaurus]
    private var archivedThesauri: [LoadedNamingThesaurus]
    private var ruleDrafts: [NamingRuleDraft]
    private var thesaurusDrafts: [ImportedThesaurusDraft]
    private var feedbackRecords: [PersistedNamingFeedback]

    public init(catalog: NamingRuntimeCatalog = .fallback()) {
        self.activeRules = catalog.active_rules
        self.archivedRules = catalog.archived_rules
        self.activeThesauri = catalog.active_thesauri
        self.archivedThesauri = catalog.archived_thesauri
        self.ruleDrafts = catalog.rule_drafts
        self.thesaurusDrafts = catalog.thesaurus_drafts
        self.feedbackRecords = catalog.feedback_records
    }

    public func loadRuntimeCatalog() throws -> NamingRuntimeCatalog {
        NamingRuntimeCatalog(
            active_rules: activeRules,
            draft_rule_records: ruleDrafts.map { draft in
                LoadedNamingRule(
                    rule_id: draft.proposed_rule.id,
                    version: draft.proposed_rule.version,
                    status: .draft,
                    source: .memory,
                    loaded_from: draft.draft_id,
                    is_fallback: false,
                    updated_at: draft.created_at,
                    definition: draft.proposed_rule
                )
            },
            archived_rules: archivedRules,
            active_thesauri: activeThesauri,
            archived_thesauri: archivedThesauri,
            rule_drafts: ruleDrafts,
            thesaurus_drafts: thesaurusDrafts,
            feedback_records: feedbackRecords,
            fallback_active: activeRules.allSatisfy(\.is_fallback)
        )
    }

    public func listActiveRules() throws -> [LoadedNamingRule] { activeRules }
    public func listDraftRules() throws -> [LoadedNamingRule] {
        try loadRuntimeCatalog().draft_rule_records
    }
    public func listArchivedRules() throws -> [LoadedNamingRule] { archivedRules }
    public func loadRule(id: String, includeDrafts: Bool) throws -> LoadedNamingRule? {
        try loadRuntimeCatalog().ruleRecord(id: id, includeDrafts: includeDrafts)
    }
    public func saveRule(_ rule: NamingRuleDefinition, filename: String?) throws -> LoadedNamingRule {
        let record = LoadedNamingRule(
            rule_id: rule.id,
            version: rule.version,
            status: .active,
            source: .memory,
            loaded_from: filename,
            is_fallback: false,
            updated_at: Date(),
            definition: rule
        )
        activeRules.removeAll { $0.rule_id == rule.id }
        activeRules.append(record)
        return record
    }

    public func listActiveThesauri() throws -> [LoadedNamingThesaurus] { activeThesauri }
    public func listArchivedThesauri() throws -> [LoadedNamingThesaurus] { archivedThesauri }
    public func loadThesaurus(id: String) throws -> LoadedNamingThesaurus? {
        activeThesauri.first(where: { $0.thesaurus_id == id }) ?? archivedThesauri.first(where: { $0.thesaurus_id == id })
    }
    public func saveThesaurus(_ thesaurus: NamingThesaurus, filename: String?) throws -> LoadedNamingThesaurus {
        let record = LoadedNamingThesaurus(
            thesaurus_id: thesaurus.thesaurus_id,
            version: thesaurus.version,
            status: .active,
            source: .memory,
            loaded_from: filename,
            is_fallback: false,
            updated_at: Date(),
            definition: thesaurus
        )
        activeThesauri.removeAll { $0.thesaurus_id == thesaurus.thesaurus_id }
        activeThesauri.append(record)
        return record
    }

    public func listRuleDrafts() throws -> [NamingRuleDraft] { ruleDrafts }
    public func listThesaurusDrafts() throws -> [ImportedThesaurusDraft] { thesaurusDrafts }
    public func loadThesaurusDraft(id: String) throws -> ImportedThesaurusDraft? {
        thesaurusDrafts.first(where: { $0.draft_id == id })
    }
    public func saveRuleDraft(_ draft: NamingRuleDraft) throws -> URL {
        ruleDrafts.removeAll { $0.draft_id == draft.draft_id }
        ruleDrafts.append(draft)
        return URL(fileURLWithPath: "/memory/\(draft.draft_id).json")
    }
    public func saveThesaurusDraft(_ draft: ImportedThesaurusDraft) throws -> URL {
        thesaurusDrafts.removeAll { $0.draft_id == draft.draft_id }
        thesaurusDrafts.append(draft)
        return URL(fileURLWithPath: "/memory/\(draft.draft_id).json")
    }

    public func listFeedback(ruleID: String?) throws -> [PersistedNamingFeedback] {
        if let ruleID {
            return feedbackRecords.filter { $0.rule_id == ruleID }
        }
        return feedbackRecords
    }

    public func recordFeedback(_ feedback: PersistedNamingFeedback) throws -> URL {
        feedbackRecords.append(feedback)
        return URL(fileURLWithPath: "/memory/\(feedback.feedback_id).json")
    }
}
