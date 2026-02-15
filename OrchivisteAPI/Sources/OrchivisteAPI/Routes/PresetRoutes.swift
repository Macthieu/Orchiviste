import Vapor

func registerPresetRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.get("presets") { req async throws -> [Preset] in
            let disk = ConfigLoader.loadPresets()
            let memory = await req.application.appState.listPresets()
            let merged = Dictionary(uniqueKeysWithValues: (disk + memory).map { ($0.id, $0) })
            return Array(merged.values)
        }

        v1.post("presets") { req async throws -> Preset in
            let preset = try req.content.decode(Preset.self)
            try validatePreset(preset)
            await req.application.appState.upsertPreset(preset)
            try ConfigLoader.savePreset(preset)
            return preset
        }
    }
}

private func validatePreset(_ preset: Preset) throws {
    guard !preset.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "Preset id is required.")
    }
    guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "Preset name is required.")
    }
    guard !preset.name_format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "Preset name_format is required.")
    }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    if preset.id.rangeOfCharacter(from: allowed.inverted) != nil {
        throw Abort(.badRequest, reason: "Preset id may only contain letters, numbers, '-' and '_'.")
    }
}
