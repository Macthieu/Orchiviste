import Vapor

func registerAnalyseRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("analyse") { req async throws -> AnalysisResponse in
            let body = try req.content.decode(AnalysisRequest.self)
            let presets = ConfigLoader.loadPresets()
            let preset = presets.first { $0.id == body.preset_id } ?? presets.first
            let routing = ConfigLoader.loadRoutingMap()
            let classCode = preset?.class_code ?? routing?.mappings.keys.first
            return AnalysisStub.make(
                fileId: body.file_id,
                text: body.text,
                preset: preset,
                classCode: classCode
            )
        }
    }
}
