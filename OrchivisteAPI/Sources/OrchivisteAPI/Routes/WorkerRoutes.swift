import Vapor

func registerWorkerRoutes(_ app: Application) {
    app.group("v1", "workers") { workers in
        workers.post("enroll") { req async throws -> WorkerRecord in
            let body = try req.content.decode(WorkerEnrollRequest.self)
            return await req.application.appState.enrollWorker(
                name: body.name,
                capabilities: body.capabilities ?? []
            )
        }

        workers.post(":id", "approve") { req async throws -> WorkerRecord in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr),
                  let worker = await req.application.appState.approveWorker(id: id) else {
                throw Abort(.notFound, reason: "Worker not found.")
            }
            return worker
        }

        workers.post(":id", "heartbeat") { req async throws -> WorkerRecord in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr) else {
                throw Abort(.badRequest, reason: "Invalid worker id.")
            }
            let body = try req.content.decode(WorkerHeartbeatRequest.self)
            guard let worker = await req.application.appState.heartbeatWorker(id: id, payload: body) else {
                throw Abort(.notFound, reason: "Worker not found.")
            }
            return worker
        }

        workers.get { req async throws -> [WorkerRecord] in
            await req.application.appState.listWorkers()
        }
    }
}
