import Foundation
import Vapor

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

    static func loadPresets() -> [Preset] {
        let dir = baseDir().appendingPathComponent("presets", isDirectory: true)
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

    static func savePreset(_ preset: Preset) throws {
        let dir = baseDir().appendingPathComponent("presets", isDirectory: true)
        try ensureDir(dir)
        let url = dir.appendingPathComponent("\(preset.id).json")
        let data = try JSONEncoder().encode(preset)
        try data.write(to: url, options: [.atomic])
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
}
