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
            var resolvedJobID: UUID?
            if let jobId = UUID(uuidString: fileId) {
                let inMemory = await req.application.appState.job(id: jobId)
                let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: req.db)
                if let job = inMemory ?? persisted {
                await req.application.appState.cacheJob(job)
                if job.status == .needs_review {
                    throw Abort(.conflict, reason: "Job requires human review before routing.")
                }
                if job.status == .pending || job.status == .running {
                    throw Abort(.conflict, reason: "Job analysis is not completed yet.")
                }
                suggestedCode = job.suggestedClassCode
                resolvedJobID = jobId
                }
            }

            let classCode = suggestedCode ?? routing.mappings.keys.first ?? "UNCLASSIFIED"

            guard let target = routing.mappings[classCode] ?? routing.mappings.values.first else {
                throw Abort(.notFound, reason: "No routing target for class code.")
            }

            let year = String(Calendar.current.component(.year, from: Date()))
            let resolved = target.folder_expr
                .replacingOccurrences(of: "{code}", with: classCode)
                .replacingOccurrences(of: "{year}", with: year)

            if let resolvedJobID,
               let updatedJob = await req.application.appState.markRouted(jobId: resolvedJobID, classCode: classCode) {
                try await JobPersistenceRepository.upsert(job: updatedJob, on: req.db)
                await EventPublisher.publish(
                    type: "job.routed",
                    payload: ["job_id": resolvedJobID.uuidString, "class_code": classCode],
                    application: req.application,
                    database: req.db,
                    logger: req.logger
                )
            } else {
                await EventPublisher.publish(
                    type: "route.ready",
                    payload: ["file_id": fileId, "class_code": classCode],
                    application: req.application,
                    database: req.db,
                    logger: req.logger
                )
            }

            return RoutingResponse(
                file_id: fileId,
                class_code: classCode,
                target: target,
                resolved_folder: resolved
            )
        }
    }
}
