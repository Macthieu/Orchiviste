import Vapor

func registerJobRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.get("jobs", ":id") { req async throws -> JobRecord in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr) else {
                throw Abort(.badRequest, reason: "Invalid job id.")
            }
            if let inMemory = await req.application.appState.job(id: id) {
                return inMemory
            }
            if let persisted = try await JobPersistenceRepository.fetchJob(id: id, on: req.db) {
                await req.application.appState.cacheJob(persisted)
                return persisted
            }
            throw Abort(.notFound, reason: "Job not found.")
        }

        v1.post("jobs", ":id", "cancel") { req async throws -> JobCancelResponse in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr) else {
                throw Abort(.badRequest, reason: "Invalid job id.")
            }

            if await req.application.appState.job(id: id) == nil,
               let persisted = try await JobPersistenceRepository.fetchJob(id: id, on: req.db) {
                await req.application.appState.cacheJob(persisted)
            }

            guard let current = await req.application.appState.job(id: id) else {
                throw Abort(.notFound, reason: "Job not found.")
            }
            if current.status == .completed || current.status == .failed || current.status == .cancelled {
                throw Abort(.conflict, reason: "Job can no longer be cancelled.")
            }
            guard let job = await req.application.appState.cancelJob(id: id) else {
                throw Abort(.notFound, reason: "Job not found.")
            }
            try await JobPersistenceRepository.upsert(job: job, on: req.db)
            try await JobPersistenceRepository.appendEvent(
                type: "job.cancelled",
                payload: ["job_id": id.uuidString],
                on: req.db
            )
            return JobCancelResponse(id: job.id, status: job.status)
        }
    }
}
