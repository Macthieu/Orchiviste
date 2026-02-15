import Foundation
import Vapor

func registerWorkerRoutes(_ app: Application) {
    app.group("v1", "workers") { workers in
        workers.post("enroll") { req async throws -> WorkerRecord in
            let body = try req.content.decode(WorkerEnrollRequest.self)
            guard !body.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Abort(.badRequest, reason: "Le nom de l'agent est requis.")
            }
            let worker = await req.application.appState.enrollWorker(
                name: body.name,
                capabilities: body.capabilities ?? []
            )
            await EventPublisher.publish(
                type: "worker.enrolled",
                payload: ["worker_id": worker.id.uuidString],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return worker
        }

        workers.get("queue", "stats") { req async throws -> QueueStatsResponse in
            await RedisQueueService.queueStats(application: req.application, logger: req.logger)
        }

        workers.post(":id", "approve") { req async throws -> WorkerRecord in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr) else {
                throw Abort(.badRequest, reason: "Identifiant d'agent invalide.")
            }
            guard let worker = await req.application.appState.approveWorker(id: id) else {
                throw Abort(.notFound, reason: "Agent introuvable.")
            }
            await EventPublisher.publish(
                type: "worker.approved",
                payload: ["worker_id": worker.id.uuidString],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return worker
        }

        workers.post(":id", "heartbeat") { req async throws -> WorkerRecord in
            guard let idStr = req.parameters.get("id"),
                  let id = UUID(uuidString: idStr) else {
                throw Abort(.badRequest, reason: "Identifiant d'agent invalide.")
            }
            let body = try req.content.decode(WorkerHeartbeatRequest.self)
            guard let existing = await req.application.appState.worker(id: id) else {
                throw Abort(.notFound, reason: "Agent introuvable.")
            }
            guard existing.status == .approved else {
                throw Abort(.conflict, reason: "L'agent n'est pas approuvé.")
            }
            if let token = existing.token, !token.isEmpty {
                guard req.headers.bearerAuthorization?.token == token else {
                    throw Abort(.unauthorized, reason: "Jeton agent invalide.")
                }
            }
            guard let worker = await req.application.appState.heartbeatWorker(id: id, payload: body) else {
                throw Abort(.notFound, reason: "Agent introuvable.")
            }
            await EventPublisher.publish(
                type: "worker.heartbeat",
                payload: ["worker_id": worker.id.uuidString],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return worker
        }

        workers.get { req async throws -> [WorkerRecord] in
            await req.application.appState.listWorkers()
        }
    }
}
