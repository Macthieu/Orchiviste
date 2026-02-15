import Vapor

func registerRoutingRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("route", ":file_id") { req async throws -> RoutingResponse in
            guard let fileId = req.parameters.get("file_id") else {
                throw Abort(.badRequest, reason: "file_id is required.")
            }
            guard let routing = ConfigLoader.loadRoutingMap() else {
                throw Abort(.notFound, reason: "routing map not found.")
            }

            var suggestedCode: String?
            if let jobId = UUID(uuidString: fileId),
               let job = await req.application.appState.job(id: jobId) {
                suggestedCode = job.suggestedClassCode
            }

            let classCode = suggestedCode ?? routing.mappings.keys.first ?? "UNCLASSIFIED"

            guard let target = routing.mappings[classCode] ?? routing.mappings.values.first else {
                throw Abort(.notFound, reason: "No routing target for class code.")
            }

            let year = String(Calendar.current.component(.year, from: Date()))
            let resolved = target.folder_expr
                .replacingOccurrences(of: "{code}", with: classCode)
                .replacingOccurrences(of: "{year}", with: year)

            await req.application.appState.addEvent(type: "route.ready", payload: ["file_id": fileId, "class_code": classCode])

            return RoutingResponse(
                file_id: fileId,
                class_code: classCode,
                target: target,
                resolved_folder: resolved
            )
        }
    }
}
