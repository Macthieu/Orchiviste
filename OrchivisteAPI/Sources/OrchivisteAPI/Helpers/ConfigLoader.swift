import Foundation
import Vapor

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
}
