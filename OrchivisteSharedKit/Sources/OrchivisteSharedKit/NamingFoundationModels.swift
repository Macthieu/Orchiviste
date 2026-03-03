import Foundation

public enum NamingImportStrategy: String, Codable, CaseIterable, Sendable {
    case merge
    case replace
    case draft
}

public enum NamingValidationLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public enum ThesaurusConflictKind: String, Codable, Sendable {
    case aliasAlreadyExists
    case canonicalMismatch
    case duplicateEntry
}

public struct NamingSourceMetadata: Codable, Hashable, Sendable {
    public let fileName: String?
    public let fileExtension: String?
    public let originalName: String?
    public let hints: [String: String]?

    public init(
        fileName: String? = nil,
        fileExtension: String? = nil,
        originalName: String? = nil,
        hints: [String: String]? = nil
    ) {
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.originalName = originalName
        self.hints = hints
    }
}

public struct NamingRuleCondition: Codable, Sendable {
    public let signals_any: [String]?
    public let regex_any: [String]?
    public let source_document_families: [String]?

    public init(
        signals_any: [String]? = nil,
        regex_any: [String]? = nil,
        source_document_families: [String]? = nil
    ) {
        self.signals_any = signals_any
        self.regex_any = regex_any
        self.source_document_families = source_document_families
    }
}

public struct NamingFieldStrategy: Codable, Sendable {
    public let kind: String
    public let pattern: String?
    public let semantic_hint: String?
    public let stopwords: [String]?
    public let preserve_terms: [String]?
    public let examples: [String]?
    public let notes: [String]?

    public init(
        kind: String,
        pattern: String? = nil,
        semantic_hint: String? = nil,
        stopwords: [String]? = nil,
        preserve_terms: [String]? = nil,
        examples: [String]? = nil,
        notes: [String]? = nil
    ) {
        self.kind = kind
        self.pattern = pattern
        self.semantic_hint = semantic_hint
        self.stopwords = stopwords
        self.preserve_terms = preserve_terms
        self.examples = examples
        self.notes = notes
    }
}

public struct NamingFieldDefinition: Codable, Sendable {
    public let key: String
    public let label: String
    public let required: Bool
    public let strategies: [NamingFieldStrategy]
    public let notes: [String]?

    public init(
        key: String,
        label: String,
        required: Bool,
        strategies: [NamingFieldStrategy],
        notes: [String]? = nil
    ) {
        self.key = key
        self.label = label
        self.required = required
        self.strategies = strategies
        self.notes = notes
    }
}

public struct NamingValidationRule: Codable, Sendable {
    public let kind: String
    public let parameter: String?
    public let message: String?

    public init(kind: String, parameter: String? = nil, message: String? = nil) {
        self.kind = kind
        self.parameter = parameter
        self.message = message
    }
}

public struct NamingRenderingOptions: Codable, Sendable {
    public let title_source: String?
    public let title_case: String?
    public let preserve_acronyms: [String]?
    public let title_max_length: Int?
    public let sharepoint_safe_filename_length: Int?

    public init(
        title_source: String? = nil,
        title_case: String? = nil,
        preserve_acronyms: [String]? = nil,
        title_max_length: Int? = nil,
        sharepoint_safe_filename_length: Int? = nil
    ) {
        self.title_source = title_source
        self.title_case = title_case
        self.preserve_acronyms = preserve_acronyms
        self.title_max_length = title_max_length
        self.sharepoint_safe_filename_length = sharepoint_safe_filename_length
    }
}

public struct NamingFeedbackExample: Codable, Sendable {
    public let created_at: Date
    public let source_filename: String
    public let corrected_filename: String
    public let source_fields: [String: String]?
    public let corrected_fields: [String: String]?
    public let notes: String?

    public init(
        created_at: Date,
        source_filename: String,
        corrected_filename: String,
        source_fields: [String: String]? = nil,
        corrected_fields: [String: String]? = nil,
        notes: String? = nil
    ) {
        self.created_at = created_at
        self.source_filename = source_filename
        self.corrected_filename = corrected_filename
        self.source_fields = source_fields
        self.corrected_fields = corrected_fields
        self.notes = notes
    }
}

public struct NamingRuleMetadata: Codable, Sendable {
    public let suggested_class_code: String?
    public let canonical_output_label: String?
    public let rendering: NamingRenderingOptions?
    public let feedback_examples: [NamingFeedbackExample]?
    public let notes: [String]?

    public init(
        suggested_class_code: String? = nil,
        canonical_output_label: String? = nil,
        rendering: NamingRenderingOptions? = nil,
        feedback_examples: [NamingFeedbackExample]? = nil,
        notes: [String]? = nil
    ) {
        self.suggested_class_code = suggested_class_code
        self.canonical_output_label = canonical_output_label
        self.rendering = rendering
        self.feedback_examples = feedback_examples
        self.notes = notes
    }
}

public struct NamingRuleDefinition: Codable, Sendable {
    public let id: String
    public let label: String
    public let version: String
    public let document_family: String
    public let template: String
    public let conditions: NamingRuleCondition
    public let fields: [NamingFieldDefinition]
    public let normalization: [String]
    public let forbidden_terms: [String]
    public let validations: [NamingValidationRule]
    public let metadata: NamingRuleMetadata?

    public init(
        id: String,
        label: String,
        version: String,
        document_family: String,
        template: String,
        conditions: NamingRuleCondition,
        fields: [NamingFieldDefinition],
        normalization: [String],
        forbidden_terms: [String],
        validations: [NamingValidationRule],
        metadata: NamingRuleMetadata? = nil
    ) {
        self.id = id
        self.label = label
        self.version = version
        self.document_family = document_family
        self.template = template
        self.conditions = conditions
        self.fields = fields
        self.normalization = normalization
        self.forbidden_terms = forbidden_terms
        self.validations = validations
        self.metadata = metadata
    }
}

public struct NamingThesaurusTrace: Codable, Sendable {
    public let source: String?
    public let imported_at: Date?
    public let imported_version: String?

    public init(source: String? = nil, imported_at: Date? = nil, imported_version: String? = nil) {
        self.source = source
        self.imported_at = imported_at
        self.imported_version = imported_version
    }
}

public struct NamingThesaurusEntry: Codable, Sendable {
    public let canonical: String
    public let aliases: [String]
    public let kind: String?
    public let normalized_output: String?
    public let preserve_terms: [String]?
    public let notes: [String]?

    public init(
        canonical: String,
        aliases: [String],
        kind: String? = nil,
        normalized_output: String? = nil,
        preserve_terms: [String]? = nil,
        notes: [String]? = nil
    ) {
        self.canonical = canonical
        self.aliases = aliases
        self.kind = kind
        self.normalized_output = normalized_output
        self.preserve_terms = preserve_terms
        self.notes = notes
    }
}

public struct NamingThesaurus: Codable, Sendable {
    public let thesaurus_id: String
    public let version: String
    public let description: String?
    public let trace: NamingThesaurusTrace?
    public let entries: [NamingThesaurusEntry]
    public let stopwords: [String]
    public let preserve_terms: [String]

    public init(
        thesaurus_id: String,
        version: String,
        description: String? = nil,
        trace: NamingThesaurusTrace? = nil,
        entries: [NamingThesaurusEntry],
        stopwords: [String],
        preserve_terms: [String]
    ) {
        self.thesaurus_id = thesaurus_id
        self.version = version
        self.description = description
        self.trace = trace
        self.entries = entries
        self.stopwords = stopwords
        self.preserve_terms = preserve_terms
    }
}

public struct NamingRuleValidationIssue: Codable, Sendable {
    public let level: NamingValidationLevel
    public let code: String
    public let message: String
    public let field: String?

    public init(level: NamingValidationLevel, code: String, message: String, field: String? = nil) {
        self.level = level
        self.code = code
        self.message = message
        self.field = field
    }
}

public struct NamingRuleValidationRequest: Codable, Sendable {
    public let rule: NamingRuleDefinition
    public let text: String
    public let metadata: NamingSourceMetadata?
    public let thesaurus: NamingThesaurus?

    public init(
        rule: NamingRuleDefinition,
        text: String,
        metadata: NamingSourceMetadata? = nil,
        thesaurus: NamingThesaurus? = nil
    ) {
        self.rule = rule
        self.text = text
        self.metadata = metadata
        self.thesaurus = thesaurus
    }
}

public struct NamingRuleValidationResult: Codable, Sendable {
    public let detected_rule_id: String?
    public let extracted_fields: [String: String]
    public let normalized_fields: [String: String]
    public let rendered_filename: String?
    public let issues: [NamingRuleValidationIssue]

    public init(
        detected_rule_id: String?,
        extracted_fields: [String: String],
        normalized_fields: [String: String],
        rendered_filename: String?,
        issues: [NamingRuleValidationIssue]
    ) {
        self.detected_rule_id = detected_rule_id
        self.extracted_fields = extracted_fields
        self.normalized_fields = normalized_fields
        self.rendered_filename = rendered_filename
        self.issues = issues
    }
}

public struct LearningDocumentSample: Codable, Sendable {
    public let file_name: String
    public let file_path: String
    public let file_extension: String
    public let text: String
    public let metadata: [String: String]?

    public init(
        file_name: String,
        file_path: String,
        file_extension: String,
        text: String,
        metadata: [String: String]? = nil
    ) {
        self.file_name = file_name
        self.file_path = file_path
        self.file_extension = file_extension
        self.text = text
        self.metadata = metadata
    }
}

public struct RuleLearningRequest: Codable, Sendable {
    public let folder_path: String
    public let sample_size: Int?
    public let extensions: [String]?

    public init(folder_path: String, sample_size: Int? = nil, extensions: [String]? = nil) {
        self.folder_path = folder_path
        self.sample_size = sample_size
        self.extensions = extensions
    }
}

public struct RuleLearningReport: Codable, Sendable {
    public let scanned_files: Int
    public let sampled_files: Int
    public let detected_tokens: [String]
    public let suggested_synonyms: [String: [String]]
    public let inferred_transformations: [String]
    public let suggested_stopwords: [String]
    public let examples_before_after: [[String: String]]
    public let warnings: [String]

    public init(
        scanned_files: Int,
        sampled_files: Int,
        detected_tokens: [String],
        suggested_synonyms: [String: [String]],
        inferred_transformations: [String],
        suggested_stopwords: [String],
        examples_before_after: [[String: String]],
        warnings: [String]
    ) {
        self.scanned_files = scanned_files
        self.sampled_files = sampled_files
        self.detected_tokens = detected_tokens
        self.suggested_synonyms = suggested_synonyms
        self.inferred_transformations = inferred_transformations
        self.suggested_stopwords = suggested_stopwords
        self.examples_before_after = examples_before_after
        self.warnings = warnings
    }
}

public struct NamingRuleDraft: Codable, Sendable {
    public let draft_id: String
    public let created_at: Date
    public let source_folder: String
    public let needs_review: Bool
    public let confidence: Double
    public let proposed_rule: NamingRuleDefinition
    public let proposed_thesaurus: NamingThesaurus?
    public let report: RuleLearningReport

    public init(
        draft_id: String,
        created_at: Date,
        source_folder: String,
        needs_review: Bool,
        confidence: Double,
        proposed_rule: NamingRuleDefinition,
        proposed_thesaurus: NamingThesaurus?,
        report: RuleLearningReport
    ) {
        self.draft_id = draft_id
        self.created_at = created_at
        self.source_folder = source_folder
        self.needs_review = needs_review
        self.confidence = confidence
        self.proposed_rule = proposed_rule
        self.proposed_thesaurus = proposed_thesaurus
        self.report = report
    }
}

public struct ThesaurusConflict: Codable, Sendable {
    public let kind: ThesaurusConflictKind
    public let alias: String?
    public let existing_canonical: String?
    public let incoming_canonical: String?
    public let message: String

    public init(
        kind: ThesaurusConflictKind,
        alias: String? = nil,
        existing_canonical: String? = nil,
        incoming_canonical: String? = nil,
        message: String
    ) {
        self.kind = kind
        self.alias = alias
        self.existing_canonical = existing_canonical
        self.incoming_canonical = incoming_canonical
        self.message = message
    }
}

public struct ThesaurusMergePreview: Codable, Sendable {
    public let strategy: NamingImportStrategy
    public let target_thesaurus_id: String
    public let merged: NamingThesaurus
    public let conflicts: [ThesaurusConflict]
    public let warnings: [String]

    public init(
        strategy: NamingImportStrategy,
        target_thesaurus_id: String,
        merged: NamingThesaurus,
        conflicts: [ThesaurusConflict],
        warnings: [String]
    ) {
        self.strategy = strategy
        self.target_thesaurus_id = target_thesaurus_id
        self.merged = merged
        self.conflicts = conflicts
        self.warnings = warnings
    }
}

public struct ThesaurusImportPreviewRequest: Codable, Sendable {
    public let target_thesaurus_id: String?
    public let strategy: NamingImportStrategy?
    public let format: String?
    public let raw_text: String
    public let source_name: String?

    public init(
        target_thesaurus_id: String? = nil,
        strategy: NamingImportStrategy? = nil,
        format: String? = nil,
        raw_text: String,
        source_name: String? = nil
    ) {
        self.target_thesaurus_id = target_thesaurus_id
        self.strategy = strategy
        self.format = format
        self.raw_text = raw_text
        self.source_name = source_name
    }
}

public struct ThesaurusImportConfirmRequest: Codable, Sendable {
    public let draft_id: String
    public let strategy: NamingImportStrategy?
    public let target_thesaurus_id: String?

    public init(
        draft_id: String,
        strategy: NamingImportStrategy? = nil,
        target_thesaurus_id: String? = nil
    ) {
        self.draft_id = draft_id
        self.strategy = strategy
        self.target_thesaurus_id = target_thesaurus_id
    }
}

public struct ImportedThesaurusDraft: Codable, Sendable {
    public let draft_id: String
    public let created_at: Date
    public let source_name: String
    public let format: String
    public let imported: NamingThesaurus
    public let preview: ThesaurusMergePreview

    public init(
        draft_id: String,
        created_at: Date,
        source_name: String,
        format: String,
        imported: NamingThesaurus,
        preview: ThesaurusMergePreview
    ) {
        self.draft_id = draft_id
        self.created_at = created_at
        self.source_name = source_name
        self.format = format
        self.imported = imported
        self.preview = preview
    }
}

public struct NamingDraftIndex: Codable, Sendable {
    public let rule_drafts: [NamingRuleDraft]
    public let thesaurus_drafts: [ImportedThesaurusDraft]

    public init(rule_drafts: [NamingRuleDraft], thesaurus_drafts: [ImportedThesaurusDraft]) {
        self.rule_drafts = rule_drafts
        self.thesaurus_drafts = thesaurus_drafts
    }
}
