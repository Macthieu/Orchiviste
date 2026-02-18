import Vapor
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif
import OrchivisteSharedKit

// --------- Modèles d’E/S ----------
struct IngestRequest: Content {
    let fileURL: String
    let source: JobSource
    let tags: [String]?
    let hints: AnalysisHints?

    enum CodingKeys: String, CodingKey {
        case fileURL
        case source
        case tags
        case hints
    }

    init(fileURL: String, source: JobSource, tags: [String]? = nil, hints: AnalysisHints? = nil) {
        self.fileURL = fileURL
        self.source = source
        self.tags = tags
        self.hints = hints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileURL = try container.decode(String.self, forKey: .fileURL)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        hints = try container.decodeIfPresent(AnalysisHints.self, forKey: .hints)

        if let sourceObj = try? container.decode(JobSource.self, forKey: .source) {
            source = sourceObj
            return
        }
        if let sourceStr = try? container.decode(String.self, forKey: .source) {
            source = JobSource(kind: sourceStr, url: nil, site: nil, library: nil, itemId: nil)
            return
        }
        source = JobSource(kind: "local", url: nil, site: nil, library: nil, itemId: nil)
    }
}

struct IngestsResponse: Content {
    let status: String
    let taskId: String
}

extension IngestRequest {
    func idempotencyFingerprint() -> String {
        let normalizedTags = (tags ?? []).sorted().joined(separator: ",")
        let normalized = [
            fileURL,
            source.kind,
            source.url ?? "",
            source.site ?? "",
            source.library ?? "",
            source.itemId ?? "",
            normalizedTags,
            hints?.session_id ?? "",
            hints?.agenda_id ?? ""
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// --------- Routes ----------
func registerIngestRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("ingest") { req async throws -> Response in
            let body = try req.content.decode(IngestRequest.self)
            let idempotencyKey = req.headers.first(name: "Idempotency-Key")
            let taskId = try await enqueueIngest(
                body: body,
                idempotencyKey: idempotencyKey,
                req: req
            )
            return try queuedResponse(taskId: taskId)
        }
    }
}

func enqueueIngest(
    body: IngestRequest,
    idempotencyKey: String?,
    req: Request
) async throws -> UUID {
    guard !body.fileURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "fileURL est requis.")
    }
    let requestHash = body.idempotencyFingerprint()

    if let idempotencyKey, !idempotencyKey.isEmpty {
        if let inMemory = await req.application.appState.idempotencyEntry(for: idempotencyKey) {
            guard inMemory.requestHash == requestHash else {
                throw Abort(.conflict, reason: "Idempotency-Key est déjà utilise avec une charge differente.")
            }
            if let cached = await req.application.appState.job(id: inMemory.jobId) {
                return cached.id
            }
            if let existing = try await JobPersistenceRepository.fetchJob(id: inMemory.jobId, on: req.db) {
                await req.application.appState.cacheJob(existing)
                return existing.id
            }
            throw Abort(.conflict, reason: "Idempotency-Key pointe vers une tâche inconnue.")
        }

        if let persisted = try await JobPersistenceRepository.fetchIdempotency(key: idempotencyKey, on: req.db) {
            await req.application.appState.rememberIdempotency(
                idempotencyKey,
                requestHash: persisted.requestHash,
                jobId: persisted.jobId
            )
            guard persisted.requestHash == requestHash else {
                throw Abort(.conflict, reason: "Idempotency-Key est déjà utilise avec une charge differente.")
            }
            if let existing = try await JobPersistenceRepository.fetchJob(id: persisted.jobId, on: req.db) {
                await req.application.appState.cacheJob(existing)
                return existing.id
            }
            throw Abort(.conflict, reason: "Idempotency-Key pointe vers une tâche inconnue.")
        }
    }

    let job = await req.application.appState.createJob(
        fileURL: body.fileURL,
        source: body.source,
        tags: body.tags ?? []
    )

    try await JobPersistenceRepository.upsert(job: job, on: req.db)
    await EventPublisher.publish(
        type: "job.ingest_received",
        payload: ["job_id": job.id.uuidString],
        application: req.application,
        database: req.db,
        logger: req.logger
    )

    if let idempotencyKey, !idempotencyKey.isEmpty {
        await req.application.appState.rememberIdempotency(
            idempotencyKey,
            requestHash: requestHash,
            jobId: job.id
        )
        try await JobPersistenceRepository.saveIdempotency(
            key: idempotencyKey,
            requestHash: requestHash,
            jobId: job.id,
            on: req.db
        )
    }

    let enqueue = IngestJob(
        taskId: job.id,
        fileURL: body.fileURL,
        source: body.source.kind,
        tags: body.tags,
        enqueuedAt: Date()
    )
    let data = try JSONEncoder().encode(enqueue)

    // 2) Queue Redis (squelette MVP)
    let queueResult = await RedisQueueService.enqueueIngest(
        payload: data,
        application: req.application,
        logger: req.logger
    )
    if queueResult.enqueued {
        await EventPublisher.publish(
            type: "queue.ingest_enqueued",
            payload: ["job_id": job.id.uuidString, "queue": queueResult.queue],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
    } else {
        await RedisQueueService.enqueueDeadLetter(
            payload: data,
            reason: "redis_enqueue_failed",
            application: req.application,
            logger: req.logger
        )
        await EventPublisher.publish(
            type: "queue.ingest_dead_lettered",
            payload: ["job_id": job.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        req.logger.warning("Ingestion placee en file rejet suite a un échec d'enfilement Redis.", metadata: [
            "job_id": .string(job.id.uuidString)
        ])
    }

    return job.id
}

private func queuedResponse(taskId: UUID) throws -> Response {
    let response = Response(status: .accepted)
    try response.content.encode(
        IngestsResponse(status: "queued", taskId: taskId.uuidString)
    )
    return response
}
