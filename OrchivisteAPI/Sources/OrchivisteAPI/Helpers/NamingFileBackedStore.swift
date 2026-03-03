import Foundation
import OrchivisteAnalyseCore
import OrchivisteSharedKit
import Vapor
import Yams

struct ConfigBackedNamingArtifactLocator: NamingArtifactLocator {
    var namingBaseDirectory: URL { ConfigLoader.namingBaseDirectory() }
    var rulesDirectory: URL { ConfigLoader.namingRulesDirectory() }
    var thesaurusDirectory: URL { ConfigLoader.namingThesaurusDirectory() }
    var ruleDraftsDirectory: URL { ConfigLoader.namingRuleDraftsDirectory() }
    var thesaurusDraftsDirectory: URL { ConfigLoader.namingThesaurusDraftsDirectory() }
    var archivedRulesDirectory: URL {
        namingBaseDirectory.appendingPathComponent("archive/rules", isDirectory: true)
    }
    var archivedThesauriDirectory: URL {
        namingBaseDirectory.appendingPathComponent("archive/thesaurus", isDirectory: true)
    }
    var feedbackDirectory: URL {
        namingBaseDirectory.appendingPathComponent("feedback", isDirectory: true)
    }
}

final class FileBackedNamingStore: NamingPersistenceStore {
    private let locator: NamingArtifactLocator
    private let ruleLoader: NamingRuleLoader
    private let thesaurusLoader: NamingThesaurusLoader
    private let catalogBuilder: NamingRuntimeCatalogBuilder

    init(
        locator: NamingArtifactLocator = ConfigBackedNamingArtifactLocator(),
        ruleLoader: NamingRuleLoader = .init(),
        thesaurusLoader: NamingThesaurusLoader = .init(),
        catalogBuilder: NamingRuntimeCatalogBuilder = .init()
    ) {
        self.locator = locator
        self.ruleLoader = ruleLoader
        self.thesaurusLoader = thesaurusLoader
        self.catalogBuilder = catalogBuilder
    }

    func loadRuntimeCatalog() throws -> NamingRuntimeCatalog {
        let activeRules = try ruleLoader.loadDirectory(
            at: locator.rulesDirectory,
            status: .active,
            source: .configFile
        )
        let archivedRules = try ruleLoader.loadDirectory(
            at: locator.archivedRulesDirectory,
            status: .archived,
            source: .archiveFile
        )
        let activeThesauri = try thesaurusLoader.loadDirectory(
            at: locator.thesaurusDirectory,
            status: .active,
            source: .configFile
        )
        let archivedThesauri = try thesaurusLoader.loadDirectory(
            at: locator.archivedThesauriDirectory,
            status: .archived,
            source: .archiveFile
        )
        let ruleDrafts = try loadStructuredDirectory(at: locator.ruleDraftsDirectory, as: NamingRuleDraft.self)
        let thesaurusDrafts = try loadStructuredDirectory(at: locator.thesaurusDraftsDirectory, as: ImportedThesaurusDraft.self)
        let feedbackRecords = try loadStructuredDirectory(at: locator.feedbackDirectory, as: PersistedNamingFeedback.self)

        return catalogBuilder.build(
            activeRules: activeRules,
            archivedRules: archivedRules,
            activeThesauri: activeThesauri,
            archivedThesauri: archivedThesauri,
            ruleDrafts: ruleDrafts,
            thesaurusDrafts: thesaurusDrafts,
            feedbackRecords: feedbackRecords
        )
    }

    func listActiveRules() throws -> [LoadedNamingRule] {
        try loadRuntimeCatalog().active_rules
    }

    func listDraftRules() throws -> [LoadedNamingRule] {
        try loadRuntimeCatalog().draft_rule_records
    }

    func listArchivedRules() throws -> [LoadedNamingRule] {
        try loadRuntimeCatalog().archived_rules
    }

    func loadRule(id: String, includeDrafts: Bool) throws -> LoadedNamingRule? {
        try loadRuntimeCatalog().ruleRecord(id: id, includeDrafts: includeDrafts)
    }

    @discardableResult
    func saveRule(_ rule: NamingRuleDefinition, filename: String?) throws -> LoadedNamingRule {
        try ConfigLoader.ensureDir(locator.rulesDirectory)
        let outputURL = locator.rulesDirectory.appendingPathComponent(sanitizedFileName(filename) ?? "\(rule.id).json")
        try writeStructuredJSON(rule, to: outputURL)
        return LoadedNamingRule(
            rule_id: rule.id,
            version: rule.version,
            status: .active,
            source: .configFile,
            loaded_from: outputURL.path,
            is_fallback: false,
            updated_at: Date(),
            definition: rule
        )
    }

    func listActiveThesauri() throws -> [LoadedNamingThesaurus] {
        try loadRuntimeCatalog().active_thesauri
    }

    func listArchivedThesauri() throws -> [LoadedNamingThesaurus] {
        try loadRuntimeCatalog().archived_thesauri
    }

    func loadThesaurus(id: String) throws -> LoadedNamingThesaurus? {
        try loadRuntimeCatalog().active_thesauri.first(where: { $0.thesaurus_id == id })
            ?? loadRuntimeCatalog().archived_thesauri.first(where: { $0.thesaurus_id == id })
    }

    @discardableResult
    func saveThesaurus(_ thesaurus: NamingThesaurus, filename: String?) throws -> LoadedNamingThesaurus {
        try ConfigLoader.ensureDir(locator.thesaurusDirectory)
        let outputURL = locator.thesaurusDirectory.appendingPathComponent(sanitizedFileName(filename) ?? "\(thesaurus.thesaurus_id).json")
        try writeStructuredJSON(thesaurus, to: outputURL)
        return LoadedNamingThesaurus(
            thesaurus_id: thesaurus.thesaurus_id,
            version: thesaurus.version,
            status: .active,
            source: .configFile,
            loaded_from: outputURL.path,
            is_fallback: false,
            updated_at: Date(),
            definition: thesaurus
        )
    }

    func listRuleDrafts() throws -> [NamingRuleDraft] {
        try loadStructuredDirectory(at: locator.ruleDraftsDirectory, as: NamingRuleDraft.self)
    }

    func listThesaurusDrafts() throws -> [ImportedThesaurusDraft] {
        try loadStructuredDirectory(at: locator.thesaurusDraftsDirectory, as: ImportedThesaurusDraft.self)
    }

    func loadThesaurusDraft(id: String) throws -> ImportedThesaurusDraft? {
        try listThesaurusDrafts().first(where: { $0.draft_id == id })
    }

    @discardableResult
    func saveRuleDraft(_ draft: NamingRuleDraft) throws -> URL {
        try ConfigLoader.ensureDir(locator.ruleDraftsDirectory)
        let outputURL = locator.ruleDraftsDirectory.appendingPathComponent("\(draft.draft_id).json")
        try writeStructuredJSON(draft, to: outputURL)
        return outputURL
    }

    @discardableResult
    func saveThesaurusDraft(_ draft: ImportedThesaurusDraft) throws -> URL {
        try ConfigLoader.ensureDir(locator.thesaurusDraftsDirectory)
        let outputURL = locator.thesaurusDraftsDirectory.appendingPathComponent("\(draft.draft_id).json")
        try writeStructuredJSON(draft, to: outputURL)
        return outputURL
    }

    func listFeedback(ruleID: String?) throws -> [PersistedNamingFeedback] {
        let records = try loadStructuredDirectory(at: locator.feedbackDirectory, as: PersistedNamingFeedback.self)
        if let ruleID {
            return records.filter { $0.rule_id == ruleID }
        }
        return records
    }

    @discardableResult
    func recordFeedback(_ feedback: PersistedNamingFeedback) throws -> URL {
        try ConfigLoader.ensureDir(locator.feedbackDirectory)
        let outputURL = locator.feedbackDirectory.appendingPathComponent("\(feedback.feedback_id).json")
        try writeStructuredJSON(feedback, to: outputURL)
        return outputURL
    }

    private func loadStructuredDirectory<T: Decodable>(at directory: URL, as type: T.Type) throws -> [T] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .compactMap { url in
                guard ["json", "yaml", "yml"].contains(url.pathExtension.lowercased()) else {
                    return nil
                }
                return try? decodeStructuredFile(url: url, as: T.self)
            }
    }

    private func decodeStructuredFile<T: Decodable>(url: URL, as type: T.Type) throws -> T {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        switch ext {
        case "json":
            return try JSONDecoder().decode(T.self, from: data)
        case "yaml", "yml":
            guard let text = String(data: data, encoding: .utf8) else {
                throw Abort(.badRequest, reason: "Fichier YAML illisible: \(url.lastPathComponent)")
            }
            return try YAMLDecoder().decode(T.self, from: text)
        default:
            throw Abort(.badRequest, reason: "Format non supporté: \(url.lastPathComponent)")
        }
    }

    private func writeStructuredJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func sanitizedFileName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
