import Foundation
import Vapor

func registerJobRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.get("jobs", ":id") { req async throws -> JobRecord in
            guard let id = jobID(from: req) else {
                throw Abort(.badRequest, reason: "Identifiant de tâche invalide.")
            }
            if let inMemory = await req.application.appState.job(id: id) {
                return inMemory
            }
            if let persisted = try await JobPersistenceRepository.fetchJob(id: id, on: req.db) {
                await req.application.appState.cacheJob(persisted)
                return persisted
            }
            throw Abort(.notFound, reason: "Tâche introuvable.")
        }

        v1.post("jobs", ":id", "cancel") { req async throws -> JobCancelResponse in
            guard let id = jobID(from: req) else {
                throw Abort(.badRequest, reason: "Identifiant de tâche invalide.")
            }

            if await req.application.appState.job(id: id) == nil,
               let persisted = try await JobPersistenceRepository.fetchJob(id: id, on: req.db) {
                await req.application.appState.cacheJob(persisted)
            }

            guard let current = await req.application.appState.job(id: id) else {
                throw Abort(.notFound, reason: "Tâche introuvable.")
            }
            if current.status == .completed || current.status == .failed || current.status == .cancelled {
                throw Abort(.conflict, reason: "La tâche ne peut plus être annulée.")
            }
            guard let job = await req.application.appState.cancelJob(id: id) else {
                throw Abort(.notFound, reason: "Tâche introuvable.")
            }
            try await JobPersistenceRepository.upsert(job: job, on: req.db)
            await EventPublisher.publish(
                type: "job.cancelled",
                payload: ["job_id": id.uuidString],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return JobCancelResponse(id: job.id, status: job.status)
        }

        v1.post("jobs", ":id", "review") { req async throws -> JobRecord in
            guard let id = jobID(from: req) else {
                throw Abort(.badRequest, reason: "Identifiant de tâche invalide.")
            }
            let review = try req.content.decode(JobReviewRequest.self)

            if await req.application.appState.job(id: id) == nil,
               let persisted = try await JobPersistenceRepository.fetchJob(id: id, on: req.db) {
                await req.application.appState.cacheJob(persisted)
            }

            guard let current = await req.application.appState.job(id: id) else {
                throw Abort(.notFound, reason: "Tâche introuvable.")
            }
            guard current.status == .needs_review else {
                throw Abort(.conflict, reason: "La tâche n'est pas en état de revue requise.")
            }
            guard let reviewed = await req.application.appState.applyReview(jobId: id, request: review) else {
                throw Abort(.notFound, reason: "Tâche introuvable.")
            }
            try await JobPersistenceRepository.upsert(job: reviewed, on: req.db)
            await EventPublisher.publish(
                type: "job.reviewed",
                payload: [
                    "job_id": id.uuidString,
                    "corrected_fields": "\(review.corrected_fields?.count ?? 0)"
                ],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            await EventPublisher.publish(
                type: "job.completed",
                payload: ["job_id": id.uuidString],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return reviewed
        }

        v1.get("jobs", ":id", "download") { req async throws -> Response in
            guard let id = jobID(from: req) else {
                throw Abort(.badRequest, reason: "Identifiant de tâche invalide.")
            }
            let job = try await resolveJob(id: id, req: req)

            if job.source.kind.lowercased() == "sharepoint",
               let url = job.source.url,
               !url.isEmpty {
                return req.redirect(to: url)
            }

            guard let localFile = resolveLocalFileURL(raw: job.fileURL),
                  FileManager.default.fileExists(atPath: localFile.path) else {
                throw Abort(.notFound, reason: "Le fichier source local est indisponible.")
            }

            var response = req.fileio.streamFile(at: localFile.path)
            response.headers.replaceOrAdd(
                name: .contentDisposition,
                value: "attachment; filename=\"\(localFile.lastPathComponent)\""
            )
            return response
        }
    }
}

private func resolveJob(id: UUID, req: Request) async throws -> JobRecord {
    if let inMemory = await req.application.appState.job(id: id) {
        return inMemory
    }
    if let persisted = try await JobPersistenceRepository.fetchJob(id: id, on: req.db) {
        await req.application.appState.cacheJob(persisted)
        return persisted
    }
    throw Abort(.notFound, reason: "Tâche introuvable.")
}

private func jobID(from req: Request) -> UUID? {
    req.parameters.get("id").flatMap(UUID.init(uuidString:))
}

private func resolveLocalFileURL(raw: String) -> URL? {
    if let url = URL(string: raw), url.isFileURL {
        return url
    }
    if raw.hasPrefix("/") {
        return URL(fileURLWithPath: raw)
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return cwd.appendingPathComponent(raw)
}
