import Foundation
import Vapor

func registerWorkerRoutes(_ app: Application) {
    app.group("v1", "workers") { workers in
        workers.post("enroll") { req async throws -> WorkerRecord in
            let body = try req.content.decode(WorkerEnrollRequest.self)
            guard !body.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Abort(.badRequest, reason: "Le nom de l'agent est requis.")
            }
            let worker = await enrollWorkerWithPersistence(
                name: body.name,
                capabilities: body.capabilities ?? [],
                req: req
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
            guard let existing = await resolveWorker(id: id, req: req) else {
                throw Abort(.notFound, reason: "Agent introuvable.")
            }
            let worker = await approveWorkerWithPersistence(id: id, fallback: existing, req: req)
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
            guard let existing = await resolveWorker(id: id, req: req) else {
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
            let worker = await heartbeatWorkerWithPersistence(
                id: id,
                payload: body,
                fallback: existing,
                req: req
            )
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
            if let persisted = try? await JobPersistenceRepository.listWorkers(on: req.db) {
                await req.application.appState.cacheWorkers(persisted)
                return persisted
            }
            return await req.application.appState.listWorkers()
        }
    }
}

private func resolveWorker(id: UUID, req: Request) async -> WorkerRecord? {
    if let inMemory = await req.application.appState.worker(id: id) {
        return inMemory
    }
    if let worker = try? await JobPersistenceRepository.fetchWorker(id: id, on: req.db) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return nil
}

private func enrollWorkerWithPersistence(
    name: String,
    capabilities: [String],
    req: Request
) async -> WorkerRecord {
    if let persisted = try? await JobPersistenceRepository.enrollWorker(
        name: name,
        capabilities: capabilities,
        on: req.db
    ) {
        await req.application.appState.cacheWorker(persisted)
        return persisted
    }
    return await req.application.appState.enrollWorker(name: name, capabilities: capabilities)
}

private func approveWorkerWithPersistence(
    id: UUID,
    fallback: WorkerRecord,
    req: Request
) async -> WorkerRecord {
    if let worker = try? await JobPersistenceRepository.approveWorker(id: id, on: req.db) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return await req.application.appState.approveWorker(id: id) ?? fallback
}

private func heartbeatWorkerWithPersistence(
    id: UUID,
    payload: WorkerHeartbeatRequest,
    fallback: WorkerRecord,
    req: Request
) async -> WorkerRecord {
    if let worker = try? await JobPersistenceRepository.heartbeatWorker(
        id: id,
        payload: payload,
        on: req.db
    ) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return await req.application.appState.heartbeatWorker(id: id, payload: payload) ?? fallback
}
