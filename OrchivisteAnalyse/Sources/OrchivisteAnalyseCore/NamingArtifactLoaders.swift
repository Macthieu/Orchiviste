import Foundation
import OrchivisteSharedKit
import Yams

public enum NamingArtifactLoadingError: Error {
    case unreadableDirectory(String)
    case unsupportedFormat(String)
    case invalidPayload(String)
}

public struct NamingRuleLoader {
    public init() {}

    public func loadDirectory(
        at directory: URL,
        status: NamingArtifactStatus,
        source: NamingArtifactSourceKind
    ) throws -> [LoadedNamingRule] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .compactMap { url in
                guard isSupportedStructuredFile(url) else { return nil }
                guard let definition = try? decodeStructuredFile(at: url, as: NamingRuleDefinition.self) else {
                    return nil
                }
                let updatedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return LoadedNamingRule(
                    rule_id: definition.id,
                    version: definition.version,
                    status: status,
                    source: source,
                    loaded_from: url.path,
                    is_fallback: status == .fallback || source == .fallbackSeed,
                    updated_at: updatedAt,
                    definition: definition
                )
            }
    }
}

public struct NamingThesaurusLoader {
    public init() {}

    public func loadDirectory(
        at directory: URL,
        status: NamingArtifactStatus,
        source: NamingArtifactSourceKind
    ) throws -> [LoadedNamingThesaurus] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .compactMap { url in
                guard isSupportedStructuredFile(url) else { return nil }
                guard let definition = try? decodeStructuredFile(at: url, as: NamingThesaurus.self) else {
                    return nil
                }
                let updatedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return LoadedNamingThesaurus(
                    thesaurus_id: definition.thesaurus_id,
                    version: definition.version,
                    status: status,
                    source: source,
                    loaded_from: url.path,
                    is_fallback: status == .fallback || source == .fallbackSeed,
                    updated_at: updatedAt,
                    definition: definition
                )
            }
    }
}

public struct NamingRuntimeCatalogBuilder {
    public init() {}

    public func build(
        activeRules: [LoadedNamingRule],
        archivedRules: [LoadedNamingRule],
        activeThesauri: [LoadedNamingThesaurus],
        archivedThesauri: [LoadedNamingThesaurus],
        ruleDrafts: [NamingRuleDraft],
        thesaurusDrafts: [ImportedThesaurusDraft],
        feedbackRecords: [PersistedNamingFeedback]
    ) -> NamingRuntimeCatalog {
        let fallbackRules = activeRules.isEmpty
            ? NamingFoundationSeeds.bootstrapFallbackRules().map {
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
            }
            : []
        let fallbackThesauri = activeThesauri.isEmpty
            ? [NamingFoundationSeeds.bootstrapFallbackThesaurus()].map {
                LoadedNamingThesaurus(
                    thesaurus_id: $0.thesaurus_id,
                    version: $0.version,
                    status: .fallback,
                    source: .fallbackSeed,
                    loaded_from: nil,
                    is_fallback: true,
                    updated_at: nil,
                    definition: $0
                )
            }
            : []

        let draftRecords = ruleDrafts.map { draft in
            LoadedNamingRule(
                rule_id: draft.proposed_rule.id,
                version: draft.proposed_rule.version,
                status: .draft,
                source: .draftFile,
                loaded_from: draft.draft_id,
                is_fallback: false,
                updated_at: draft.created_at,
                definition: draft.proposed_rule
            )
        }

        return NamingRuntimeCatalog(
            active_rules: activeRules.isEmpty ? fallbackRules : activeRules,
            draft_rule_records: draftRecords,
            archived_rules: archivedRules,
            active_thesauri: activeThesauri.isEmpty ? fallbackThesauri : activeThesauri,
            archived_thesauri: archivedThesauri,
            rule_drafts: ruleDrafts,
            thesaurus_drafts: thesaurusDrafts,
            feedback_records: feedbackRecords,
            fallback_active: activeRules.isEmpty || activeThesauri.isEmpty
        )
    }
}

func decodeStructuredFile<T: Decodable>(at url: URL, as type: T.Type) throws -> T {
    let ext = url.pathExtension.lowercased()
    let data = try Data(contentsOf: url)
    switch ext {
    case "json":
        return try JSONDecoder().decode(T.self, from: data)
    case "yaml", "yml":
        guard let text = String(data: data, encoding: .utf8) else {
            throw NamingArtifactLoadingError.invalidPayload("Fichier YAML illisible: \(url.lastPathComponent)")
        }
        return try YAMLDecoder().decode(T.self, from: text)
    default:
        throw NamingArtifactLoadingError.unsupportedFormat(url.lastPathComponent)
    }
}

func encodeStructuredJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

func isSupportedStructuredFile(_ url: URL) -> Bool {
    ["json", "yaml", "yml"].contains(url.pathExtension.lowercased())
}
