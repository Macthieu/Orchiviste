import Foundation
import OrchivisteAnalyseCore
import OrchivisteSharedKit
import Vapor
import Yams

struct UIDashboardState: Codable {
    var recent_jobs_cleared_at: Date?
}

enum ConfigLoader {
    static func baseDir() -> URL {
        if let env = Environment.get("ORCHIVISTE_CONFIG_DIR") {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let cwdCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("configs", isDirectory: true)
        if FileManager.default.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        let packageRoot = sourceURL
            .deletingLastPathComponent() // ConfigLoader.swift
            .deletingLastPathComponent() // Helpers
            .deletingLastPathComponent() // OrchivisteAPI
            .deletingLastPathComponent() // Sources
        return packageRoot.appendingPathComponent("configs", isDirectory: true)
    }

    static func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    static func presetsDirectory() -> URL {
        baseDir().appendingPathComponent("presets", isDirectory: true)
    }

    static func presetURL(id: String) -> URL {
        presetsDirectory().appendingPathComponent("\(id).json")
    }

    static func examplePresetURL() -> URL {
        presetsDirectory().appendingPathComponent("example-resolution.json")
    }

    static func loadPresets() -> [Preset] {
        let dir = presetsDirectory()
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let preset = try? JSONDecoder().decode(Preset.self, from: data) else {
                return nil
            }
            return preset
        }
    }

    static func loadPreset(id: String) -> Preset? {
        let exact = presetURL(id: id)
        if let data = try? Data(contentsOf: exact),
           let preset = try? JSONDecoder().decode(Preset.self, from: data) {
            return preset
        }
        return loadPresets().first { $0.id == id }
    }

    @discardableResult
    static func savePreset(_ preset: Preset, filename: String? = nil) throws -> URL {
        let dir = presetsDirectory()
        try ensureDir(dir)
        let safeFileName = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFileName = "\(preset.id).json"
        let outputFileName = safeFileName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackFileName
        let url = dir.appendingPathComponent(outputFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(preset)
        try data.write(to: url, options: [.atomic])
        return url
    }

    static func loadTaxonomy(id: String) -> TaxonomyRecord? {
        let dir = baseDir().appendingPathComponent("analysis/taxonomy", isDirectory: true)
        let url = dir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TaxonomyRecord.self, from: data)
    }

    static func saveTaxonomy(_ taxonomy: TaxonomyRecord) throws {
        let dir = baseDir().appendingPathComponent("analysis/taxonomy", isDirectory: true)
        try ensureDir(dir)
        let url = dir.appendingPathComponent("\(taxonomy.taxonomy_id).json")
        let data = try JSONEncoder().encode(taxonomy)
        try data.write(to: url, options: [.atomic])
    }

    static func saveAgenda(_ agenda: AgendaRecord) throws {
        let dir = baseDir().appendingPathComponent("agendas", isDirectory: true)
        try ensureDir(dir)
        let url = dir.appendingPathComponent("\(agenda.session_id).json")
        let data = try JSONEncoder().encode(agenda)
        try data.write(to: url, options: [.atomic])
    }

    static func loadAgenda(sessionId: String) -> AgendaRecord? {
        let dir = baseDir().appendingPathComponent("agendas", isDirectory: true)
        let url = dir.appendingPathComponent("\(sessionId).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgendaRecord.self, from: data)
    }

    static func loadRoutingMap() -> RoutingMap? {
        let url = baseDir().appendingPathComponent("analysis/routing/routing.map.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RoutingMap.self, from: data)
    }

    static func loadRoutingLocalSettings() -> RoutingLocalSettings? {
        let url = baseDir().appendingPathComponent("analysis/routing/local.settings.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RoutingLocalSettings.self, from: data)
    }

    static func saveRoutingLocalSettings(_ settings: RoutingLocalSettings) throws {
        let dir = baseDir().appendingPathComponent("analysis/routing", isDirectory: true)
        try ensureDir(dir)
        let url = dir.appendingPathComponent("local.settings.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: [.atomic])
    }

    static func routingRulesURL() -> URL {
        baseDir().appendingPathComponent("analysis/routing/local.rules.json")
    }

    static func loadRoutingRules() -> RoutingRuleSet? {
        let url = routingRulesURL()
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(RoutingRuleSet.self, from: data)
    }

    static func loadRoutingRulesRawJSON() -> String {
        let url = routingRulesURL()
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return "{\n  \"rules\": []\n}\n"
        }
        return text.hasSuffix("\n") ? text : "\(text)\n"
    }

    static func saveRoutingRules(_ rules: RoutingRuleSet) throws {
        let dir = baseDir().appendingPathComponent("analysis/routing", isDirectory: true)
        try ensureDir(dir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(rules)
        try data.write(to: routingRulesURL(), options: [.atomic])
    }

    static func saveRoutingRulesRawJSON(_ raw: String) throws {
        let data = Data(raw.utf8)
        let decoded = try JSONDecoder().decode(RoutingRuleSet.self, from: data)
        try saveRoutingRules(decoded)
    }

    static func renamingGuideURL() -> URL {
        baseDir().appendingPathComponent("analysis/routing/guide.md")
    }

    static func loadRenamingGuide() -> String {
        let url = renamingGuideURL()
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return """
            # Guide de renommage

            - Type: ProcesVerbal
            - Sujet: Comité de direction
            - Format conseillé: {class_code}-{type_doc}-{sujet}-{date}-{numero}
            """
        }
        return text
    }

    static func saveRenamingGuide(_ text: String) throws {
        let dir = baseDir().appendingPathComponent("analysis/routing", isDirectory: true)
        try ensureDir(dir)
        try Data(text.utf8).write(to: renamingGuideURL(), options: [.atomic])
    }

    static func dashboardStateURL() -> URL {
        let stateDirectory: URL
        if let env = Environment.get("ORCHIVISTE_UI_STATE_DIR") {
            stateDirectory = URL(fileURLWithPath: env, isDirectory: true)
        } else {
            stateDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("orchiviste-ui", isDirectory: true)
        }
        return stateDirectory.appendingPathComponent("dashboard.state.json")
    }

    static func loadDashboardState() -> UIDashboardState? {
        let url = dashboardStateURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UIDashboardState.self, from: data)
    }

    static func saveDashboardState(_ state: UIDashboardState) throws {
        let dir = dashboardStateURL().deletingLastPathComponent()
        try ensureDir(dir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        try data.write(to: dashboardStateURL(), options: [.atomic])
    }

    static func namingBaseDirectory() -> URL {
        baseDir().appendingPathComponent("naming", isDirectory: true)
    }

    static func namingRulesDirectory() -> URL {
        namingBaseDirectory().appendingPathComponent("rules", isDirectory: true)
    }

    static func namingThesaurusDirectory() -> URL {
        namingBaseDirectory().appendingPathComponent("thesaurus", isDirectory: true)
    }

    static func namingRuleDraftsDirectory() -> URL {
        namingBaseDirectory().appendingPathComponent("drafts/rules", isDirectory: true)
    }

    static func namingThesaurusDraftsDirectory() -> URL {
        namingBaseDirectory().appendingPathComponent("drafts/thesaurus", isDirectory: true)
    }

    static func loadNamingRules() -> [NamingRuleDefinition] {
        let loaded = loadStructuredDirectory(
            at: namingRulesDirectory(),
            as: NamingRuleDefinition.self
        )
        return loaded.isEmpty ? NamingFoundationSeeds.defaultRules() : loaded
    }

    static func loadNamingRule(id: String) -> NamingRuleDefinition? {
        loadNamingRules().first { $0.id == id }
    }

    @discardableResult
    static func saveNamingRule(_ rule: NamingRuleDefinition, filename: String? = nil) throws -> URL {
        let dir = namingRulesDirectory()
        try ensureDir(dir)
        let safeFileName = (filename?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? filename : nil)
            ?? "\(rule.id).json"
        let url = dir.appendingPathComponent(safeFileName)
        try saveJSON(rule, to: url)
        return url
    }

    static func loadNamingThesauri() -> [NamingThesaurus] {
        let loaded = loadStructuredDirectory(
            at: namingThesaurusDirectory(),
            as: NamingThesaurus.self
        )
        return loaded.isEmpty ? [NamingFoundationSeeds.defaultThesaurus()] : loaded
    }

    static func loadNamingThesaurus(id: String) -> NamingThesaurus? {
        loadNamingThesauri().first { $0.thesaurus_id == id }
    }

    @discardableResult
    static func saveNamingThesaurus(_ thesaurus: NamingThesaurus, filename: String? = nil) throws -> URL {
        let dir = namingThesaurusDirectory()
        try ensureDir(dir)
        let safeFileName = (filename?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? filename : nil)
            ?? "\(thesaurus.thesaurus_id).json"
        let url = dir.appendingPathComponent(safeFileName)
        try saveJSON(thesaurus, to: url)
        return url
    }

    static func loadNamingRuleDrafts() -> [NamingRuleDraft] {
        loadStructuredDirectory(at: namingRuleDraftsDirectory(), as: NamingRuleDraft.self)
    }

    @discardableResult
    static func saveNamingRuleDraft(_ draft: NamingRuleDraft) throws -> URL {
        let dir = namingRuleDraftsDirectory()
        try ensureDir(dir)
        let url = dir.appendingPathComponent("\(draft.draft_id).json")
        try saveJSON(draft, to: url)
        return url
    }

    static func loadNamingThesaurusDrafts() -> [ImportedThesaurusDraft] {
        loadStructuredDirectory(at: namingThesaurusDraftsDirectory(), as: ImportedThesaurusDraft.self)
    }

    static func loadNamingThesaurusDraft(id: String) -> ImportedThesaurusDraft? {
        loadNamingThesaurusDrafts().first { $0.draft_id == id }
    }

    @discardableResult
    static func saveNamingThesaurusDraft(_ draft: ImportedThesaurusDraft) throws -> URL {
        let dir = namingThesaurusDraftsDirectory()
        try ensureDir(dir)
        let url = dir.appendingPathComponent("\(draft.draft_id).json")
        try saveJSON(draft, to: url)
        return url
    }

    private static func loadStructuredDirectory<T: Decodable>(at directory: URL, as type: T.Type) -> [T] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items.compactMap { url in
            guard ["json", "yaml", "yml"].contains(url.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            if url.pathExtension.lowercased() == "json" {
                return try? JSONDecoder().decode(T.self, from: data)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return try? YAMLDecoder().decode(T.self, from: text)
        }
    }

    private static func saveJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
