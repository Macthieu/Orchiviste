import Foundation
import Vapor

enum ConfigLoader {
    static func baseDir() -> URL {
        if let env = Environment.get("ORCHIVISTE_CONFIG_DIR") {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("configs", isDirectory: true)
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
}
