import Vapor

func registerPresetRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.get("presets") { req async throws -> [Preset] in
            let disk = ConfigLoader.loadPresets()
            let memory = await req.application.appState.listPresets()
            return mergePresets(disk: disk, memory: memory)
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

func mergePresets(disk: [Preset], memory: [Preset]) -> [Preset] {
    var byID: [String: Preset] = [:]
    for preset in disk {
        byID[preset.id] = preset
    }
    for preset in memory {
        byID[preset.id] = preset
    }
    return byID.values.sorted {
        $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
    }
}

func validatePreset(_ preset: Preset) throws {
    guard !preset.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "L'identifiant du préréglage est requis.")
    }
    guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "Le nom du préréglage est requis.")
    }
    guard !preset.name_format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "Le champ name_format est requis.")
    }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    if preset.id.rangeOfCharacter(from: allowed.inverted) != nil {
        throw Abort(.badRequest, reason: "L'identifiant du préréglage n'accepte que lettres, chiffres, '-' et '_'.")
    }
}
