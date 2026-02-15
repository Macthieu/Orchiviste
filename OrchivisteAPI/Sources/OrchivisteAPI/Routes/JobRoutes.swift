import Vapor

func registerJobRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.get("jobs", ":id") { req async throws -> JobRecord in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr),
                  let job = await req.application.appState.job(id: id) else {
                throw Abort(.notFound, reason: "Job not found.")
            }
            return job
        }

        v1.post("jobs", ":id", "cancel") { req async throws -> JobCancelResponse in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr),
                  let job = await req.application.appState.cancelJob(id: id) else {
                throw Abort(.notFound, reason: "Job not found.")
            }
            return JobCancelResponse(id: job.id, status: job.status)
        }
    }
}
