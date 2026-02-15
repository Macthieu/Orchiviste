import Vapor
import RediStack
import NIOCore
import Foundation
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

// --------- Routes ----------
func registerIngestRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("ingest") { req async throws -> IngestsResponse in
            // 1) Parse du body + préparation du job
            let body = try req.content.decode(IngestRequest.self)
            if let key = req.headers.first(name: "Idempotency-Key"),
               let existingId = await req.application.appState.getOrCreateJobId(for: key),
               let existing = await req.application.appState.job(id: existingId) {
                return IngestsResponse(status: "queued", taskId: existing.id.uuidString)
            }

            let job = await req.application.appState.createJob(
                fileURL: body.fileURL,
                source: body.source,
                tags: body.tags ?? []
            )
            if let key = req.headers.first(name: "Idempotency-Key") {
                await req.application.appState.rememberIdempotency(key, jobId: job.id)
            }

            let enqueue = IngestJob(
                taskId: job.id,
                fileURL: body.fileURL,
                source: body.source.kind,
                tags: body.tags,
                enqueuedAt: Date()
            )

            let data = try JSONEncoder().encode(enqueue)

            // 2) Si ORCHIVISTE_REDIS_URL est défini : push dans Redis
            if let redisURLStr = Environment.get("ORCHIVISTE_REDIS_URL"),
               let url = URL(string: redisURLStr),
               let host = url.host {

                let port = url.port ?? 6379

                // crée une connexion Redis liée à l’event loop de la requête
                let connection = try await RedisConnection.make(
                    configuration: .init(hostname: host, port: port),
                    boundEventLoop: req.application.eventLoopGroup.next()
                ).get()
                defer { try? connection.close().wait() }

                // Encodage RESP en BulkString (RediStack)
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                let value = RESPValue.bulkString(buffer)

                // Utilise une clé de queue; RPUSH + BLPOP -> FIFO
                let queueKey = RedisKey("orchiviste:ingest")

                // RPUSH
                _ = try await connection.rpush([value], into: queueKey).get()

            } else {
                req.logger.warning("ORCHIVISTE_REDIS_URL non défini → la tâche \(job.id) n’a PAS été envoyée dans Redis.")
            }

            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 350_000_000)
                let preview = PreviewRecord(
                    jobId: job.id,
                    pages: 1,
                    textPages: [1: PreviewHelper.defaultText(page: 1)],
                    imagesByPage: [1: PreviewHelper.placeholderJPEG()],
                    createdAt: Date()
                )
                await req.application.appState.markPreviewReady(jobId: job.id, preview: preview)

                try? await Task.sleep(nanoseconds: 350_000_000)
                let diskPresets = ConfigLoader.loadPresets()
                let preset = diskPresets.first
                let routing = ConfigLoader.loadRoutingMap()
                let classCode = preset?.class_code ?? routing?.mappings.keys.first
                let analysis = AnalysisStub.make(
                    fileId: job.fileURL,
                    text: preview.textPages[1],
                    preset: preset,
                    classCode: classCode
                )
                let minConfidence = 0.7
                let needsReview = analysis.confidence < minConfidence
                await req.application.appState.attachAnalysis(jobId: job.id, analysis: analysis, needsReview: needsReview)
            }

            // 3) Toujours répondre 202/queued (asynchrone)
            return IngestsResponse(status: "queued", taskId: job.id.uuidString)
        }
    }
}
