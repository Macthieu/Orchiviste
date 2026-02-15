import Vapor

func registerRoutingRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("route", ":file_id") { req async throws -> RoutingResponse in
            guard let fileId = req.parameters.get("file_id") else {
                throw Abort(.badRequest, reason: "file_id est requis.")
            }
            guard let routing = ConfigLoader.loadRoutingMap() else {
                throw Abort(.notFound, reason: "Table de routage introuvable.")
            }

            var suggestedCode: String?
            var resolvedJobID: UUID?
            var resolvedJob: JobRecord?
            if let jobId = UUID(uuidString: fileId) {
                let inMemory = await req.application.appState.job(id: jobId)
                let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: req.db)
                if let job = inMemory ?? persisted {
                    await req.application.appState.cacheJob(job)
                    if job.status == .needs_review {
                        throw Abort(.conflict, reason: "La tâche exige une revue humaine avant le routage.")
                    }
                    if job.status == .pending || job.status == .running {
                        throw Abort(.conflict, reason: "L'analyse de la tâche n'est pas terminée.")
                    }
                    suggestedCode = job.suggestedClassCode
                    resolvedJobID = jobId
                    resolvedJob = job
                }
            }

            let classCode = suggestedCode ?? routing.mappings.keys.first ?? "UNCLASSIFIED"

            guard let target = routing.mappings[classCode] ?? routing.mappings.values.first else {
                throw Abort(.notFound, reason: "Aucune cible de routage pour ce code de classement.")
            }

            let year = String(Calendar.current.component(.year, from: Date()))
            let resolved = target.folder_expr
                .replacingOccurrences(of: "{code}", with: classCode)
                .replacingOccurrences(of: "{year}", with: year)

            var routeMode = "stub"
            var destinationURL: String?
            var movedItemID: String?

            if let resolvedJob {
                do {
                    if let graphRoute = try await SharePointGraphRouter.routeIfEnabled(
                        job: resolvedJob,
                        target: target,
                        resolvedFolder: resolved,
                        classCode: classCode,
                        req: req
                    ) {
                        routeMode = "graph"
                        destinationURL = graphRoute.destinationURL
                        movedItemID = graphRoute.movedItemID
                        await EventPublisher.publish(
                            type: "route.graph_applied",
                            payload: [
                                "job_id": resolvedJob.id.uuidString,
                                "class_code": classCode,
                                "mode": routeMode
                            ],
                            application: req.application,
                            database: req.db,
                            logger: req.logger
                        )
                    }
                } catch {
                    await EventPublisher.publish(
                        type: "route.failed",
                        payload: [
                            "job_id": resolvedJob.id.uuidString,
                            "class_code": classCode
                        ],
                        application: req.application,
                        database: req.db,
                        logger: req.logger
                    )
                    throw error
                }
            }

            if let resolvedJobID,
               let updatedJob = await req.application.appState.markRouted(jobId: resolvedJobID, classCode: classCode) {
                try await JobPersistenceRepository.upsert(job: updatedJob, on: req.db)
                await EventPublisher.publish(
                    type: "job.routed",
                    payload: [
                        "job_id": resolvedJobID.uuidString,
                        "class_code": classCode,
                        "mode": routeMode
                    ],
                    application: req.application,
                    database: req.db,
                    logger: req.logger
                )
            } else {
                await EventPublisher.publish(
                    type: "route.ready",
                    payload: [
                        "file_id": fileId,
                        "class_code": classCode,
                        "mode": routeMode
                    ],
                    application: req.application,
                    database: req.db,
                    logger: req.logger
                )
            }

            return RoutingResponse(
                file_id: fileId,
                class_code: classCode,
                target: target,
                resolved_folder: resolved,
                mode: routeMode,
                destination_url: destinationURL,
                moved_item_id: movedItemID
            )
        }
    }
}
