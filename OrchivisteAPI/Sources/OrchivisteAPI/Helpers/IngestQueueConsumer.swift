import Foundation
import Vapor
import OrchivisteSharedKit

enum IngestPipelineProcessor {
    static func process(
        ingest: IngestJob,
        application: Application,
        logger: Logger
    ) async {
        do {
            guard let job = try await resolveJob(for: ingest.taskId, application: application) else {
                await EventPublisher.publish(
                    type: "queue.ingest_orphan",
                    payload: ["job_id": ingest.taskId.uuidString],
                    application: application,
                    database: application.db,
                    logger: logger
                )
                return
            }

            let preview = PreviewRenderer.makePreview(for: job, logger: logger)
            if let previewUpdated = await application.appState.markPreviewReady(jobId: job.id, preview: preview) {
                try await JobPersistenceRepository.upsert(job: previewUpdated, on: application.db)
                await EventPublisher.publish(
                    type: "job.preview_ready",
                    payload: ["job_id": job.id.uuidString],
                    application: application,
                    database: application.db,
                    logger: logger
                )
            }

            let analysisFileID = analysisFileIdentity(for: job)
            let analysisRequest = AnalysisRequest(
                file_id: analysisFileID,
                text: analysisText(preview: preview, job: job),
                source: job.source,
                lang: nil,
                hints: nil,
                preset_id: nil,
                policy: nil
            )
            let analysis = await AnalysisProxyClient.analyzeWithFallback(
                request: analysisRequest,
                correlationId: nil,
                using: application.client,
                logger: logger
            )
            _ = try await JobAnalysisLifecycle.apply(
                analysis: analysis,
                forFileID: job.id.uuidString,
                policy: Optional<AnalysisPolicy>.none,
                application: application,
                database: application.db,
                logger: logger
            )
        } catch {
            logger.error("Echec du pipeline ingestion.", metadata: [
                "job_id": .string(ingest.taskId.uuidString),
                "error": .string(error.localizedDescription)
            ])
            if let failed = await application.appState.failJob(id: ingest.taskId) {
                try? await JobPersistenceRepository.upsert(job: failed, on: application.db)
            }
            await EventPublisher.publish(
                type: "job.failed",
                payload: ["job_id": ingest.taskId.uuidString],
                application: application,
                database: application.db,
                logger: logger
            )
            await RedisQueueService.enqueueDeadLetter(
                payload: (try? JSONEncoder().encode(ingest)) ?? Data(),
                reason: "pipeline_failed",
                application: application,
                logger: logger
            )
        }
    }

    private static func resolveJob(for id: UUID, application: Application) async throws -> JobRecord? {
        if let inMemory = await application.appState.job(id: id) {
            return inMemory
        }
        if let persisted = try await JobPersistenceRepository.fetchJob(id: id, on: application.db) {
            await application.appState.cacheJob(persisted)
            return persisted
        }
        return nil
    }

    private static func mergedPreviewText(_ preview: PreviewRecord) -> String? {
        let ordered = preview.textPages
            .sorted { $0.key < $1.key }
            .map(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.localizedCaseInsensitiveContains("Texte d'aperçu indisponible") }
            .filter { !$0.isEmpty }
        guard !ordered.isEmpty else {
            return nil
        }
        let merged = ordered.joined(separator: "\n\u{000C}\n")
        return String(merged.prefix(analysisTextLimit()))
    }

    private static func analysisText(preview: PreviewRecord, job: JobRecord) -> String? {
        let mergedPreview = mergedPreviewText(preview)
        let fileName = URL(fileURLWithPath: job.fileURL).lastPathComponent
        let tags = job.tags.joined(separator: " ")
        let context = [
            nonEmptyText("file_name: \(fileName)"),
            nonEmptyText("tags: \(tags)"),
            mergedPreview
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else {
            return nil
        }
        return String(context.prefix(analysisTextLimit()))
    }

    private static func analysisFileIdentity(for job: JobRecord) -> String {
        let fileName = URL(fileURLWithPath: job.fileURL).lastPathComponent
        guard !fileName.isEmpty else {
            return job.id.uuidString
        }
        return fileName
    }

    private static func analysisTextLimit() -> Int {
        max(2_000, Int(Environment.get("ORCHIVISTE_ANALYSE_TEXT_MAX_CHARS") ?? "120000") ?? 120000)
    }

    private static func nonEmptyText(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

final class IngestQueueConsumerLifecycle: LifecycleHandler, @unchecked Sendable {
    private var consumerTask: Task<Void, Never>?

    func didBoot(_ application: Application) throws {
        guard Environment.get("ORCHIVISTE_ENABLE_API_QUEUE_CONSUMER") != "0" else {
            application.logger.info("Consommateur ingest Redis désactivé (ORCHIVISTE_ENABLE_API_QUEUE_CONSUMER=0).")
            return
        }
        guard Environment.get("ORCHIVISTE_REDIS_URL") != nil else {
            application.logger.info("Consommateur ingest Redis inactif (ORCHIVISTE_REDIS_URL absent).")
            return
        }

        consumerTask = Task.detached(priority: .background) {
            await self.consumeLoop(application: application)
        }
    }

    func shutdown(_ application: Application) {
        consumerTask?.cancel()
        consumerTask = nil
    }

    private func consumeLoop(application: Application) async {
        let decoder = JSONDecoder()
        while !Task.isCancelled {
            guard let payload = await RedisQueueService.dequeueIngest(
                application: application,
                logger: application.logger,
                timeoutSeconds: 2
            ) else {
                continue
            }

            do {
                let ingest = try decoder.decode(IngestJob.self, from: payload)
                await EventPublisher.publish(
                    type: "queue.ingest_dequeued",
                    payload: ["job_id": ingest.taskId.uuidString],
                    application: application,
                    database: application.db,
                    logger: application.logger
                )
                await IngestPipelineProcessor.process(
                    ingest: ingest,
                    application: application,
                    logger: application.logger
                )
            } catch {
                application.logger.warning("Charge ingest Redis invalide.", metadata: [
                    "error": .string(error.localizedDescription)
                ])
                await RedisQueueService.enqueueDeadLetter(
                    payload: payload,
                    reason: "invalid_ingest_payload",
                    application: application,
                    logger: application.logger
                )
            }
        }
    }
}
