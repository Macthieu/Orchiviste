import Vapor

func registerPresetRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.get("presets") { req async throws -> [Preset] in
            await allPresets(req: req)
        }

        v1.get("presets", "example", "download") { req async throws -> Response in
            let exampleURL = ConfigLoader.examplePresetURL()
            let exampleData: Data
            if let data = try? Data(contentsOf: exampleURL) {
                exampleData = data
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                exampleData = try encoder.encode(ExamplePresets.resolution())
            }

            let response = Response(status: .ok)
            response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
            response.headers.replaceOrAdd(
                name: .contentDisposition,
                value: "attachment; filename=\"example-resolution.json\""
            )
            response.body = .init(data: exampleData)
            return response
        }

        v1.post("presets", "learn") { req async throws -> PresetLearnResponse in
            let body = try req.content.decode(PresetLearnRequest.self)
            return try PresetLearningService.learn(request: body, logger: req.logger)
        }

        v1.get("presets", ":id") { req async throws -> Preset in
            guard let rawID = req.parameters.get("id"),
                  let presetID = nonEmptyPresetValue(rawID) else {
                throw Abort(.badRequest, reason: "Identifiant de prereglage invalide.")
            }

            let presets = await allPresets(req: req)
            if let match = presets.first(where: { $0.id == presetID }) {
                return match
            }
            if presetID == "example" {
                return ExamplePresets.resolution()
            }
            throw Abort(.notFound, reason: "Prereglage introuvable.")
        }

        v1.post("presets") { req async throws -> Preset in
            let preset = try req.content.decode(Preset.self)
            try validatePreset(preset)
            await req.application.appState.upsertPreset(preset)
            _ = try ConfigLoader.savePreset(preset)
            return preset
        }
    }
}

private func allPresets(req: Request) async -> [Preset] {
    let disk = ConfigLoader.loadPresets()
    let memory = await req.application.appState.listPresets()
    return mergePresets(disk: disk, memory: memory)
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
    guard let presetID = nonEmptyPresetValue(preset.id) else {
        throw Abort(.badRequest, reason: "L'identifiant du préréglage est requis.")
    }
    guard nonEmptyPresetValue(preset.name) != nil else {
        throw Abort(.badRequest, reason: "Le nom du préréglage est requis.")
    }
    let effectiveTemplate = nonEmptyPresetValue(preset.naming?.template)
        ?? nonEmptyPresetValue(preset.name_format)
    guard let effectiveTemplate else {
        throw Abort(.badRequest, reason: "Le champ name_format est requis.")
    }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    if presetID.rangeOfCharacter(from: allowed.inverted) != nil {
        throw Abort(.badRequest, reason: "L'identifiant du préréglage n'accepte que lettres, chiffres, '-', '_' et '.'.")
    }

    let sampleName = effectiveTemplate
        .replacingOccurrences(of: "{type_doc}", with: "Resolution")
        .replacingOccurrences(of: "{type}", with: "Resolution")
        .replacingOccurrences(of: "{date}", with: "2026-02-28")
        .replacingOccurrences(of: "{numero}", with: "2026-014")
        .replacingOccurrences(of: "{sujet}", with: "Acquisition d'equipement")
        .replacingOccurrences(of: "{sujets}", with: "Acquisition d'equipement")
        .replacingOccurrences(of: "{class_code}", with: preset.class_code ?? "1223")
        .replacingOccurrences(of: "{code}", with: preset.class_code ?? "1223")
        .replacingOccurrences(of: "{preset_id}", with: presetID)
        .replacingOccurrences(of: "{preset}", with: presetID)
        .replacingOccurrences(of: "{job_id}", with: "00000000")
        .replacingOccurrences(of: "{original}", with: "Document source")
        .replacingOccurrences(of: "{comite}", with: "Conseil")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let namingError = NamingPolicy.validateCandidateStem(sampleName) {
        throw Abort(.badRequest, reason: namingError)
    }

    if let threshold = preset.review?.min_confidence,
       !(0...1).contains(threshold) {
        throw Abort(.badRequest, reason: "review.min_confidence doit etre entre 0 et 1.")
    }

    if let format = preset.export?.preferred_pdf?.format,
       !format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let normalizedFormat = format
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        let allowedFormats = ["PDF/A-2B", "PDFA-2B", "PDF/A2B"]
        guard allowedFormats.contains(normalizedFormat) else {
            throw Abort(.badRequest, reason: "Seul le format PDF/A-2b est supporte au MVP.")
        }
    }

    if let fields = preset.extract?.fields {
        for field in fields {
            guard nonEmptyPresetValue(field.key) != nil else {
                throw Abort(.badRequest, reason: "Chaque champ extract.fields doit avoir une cle.")
            }
            guard !field.strategies.isEmpty else {
                throw Abort(.badRequest, reason: "Chaque champ extract.fields doit definir au moins une strategie.")
            }
        }
    }
}

private func nonEmptyPresetValue(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
