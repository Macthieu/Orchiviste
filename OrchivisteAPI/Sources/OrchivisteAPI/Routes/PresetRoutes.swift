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
            await req.application.appState.upsertPreset(preset)
            try ConfigLoader.savePreset(preset)
            return preset
        }
    }
}
