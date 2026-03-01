import Fluent
import Vapor

enum JobAnalysisLifecycle {
    static func threshold(from policy: AnalysisPolicy?) -> Double {
        policy?.min_confidence
            ?? Environment.get("ORCHIVISTE_ANALYSE_MIN_CONFIDENCE").flatMap(Double.init)
            ?? 0.7
    }

    static func apply(
        analysis: AnalysisResponse,
        forFileID fileID: String,
        policy: AnalysisPolicy?,
        application: Application,
        database: Database,
        logger: Logger
    ) async throws -> JobRecord? {
        guard let jobId = UUID(uuidString: fileID) else {
            return nil
        }

        if await application.appState.job(id: jobId) == nil,
           let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: database) {
            await application.appState.cacheJob(persisted)
        }

        let confidenceThreshold = threshold(from: policy)
        let needsReview = (analysis.review?.needs_review ?? false) || analysis.confidence < confidenceThreshold
        guard let updatedJob = await application.appState.attachAnalysis(
            jobId: jobId,
            analysis: analysis,
            needsReview: needsReview
        ) else {
            return nil
        }

        try await JobPersistenceRepository.upsert(job: updatedJob, on: database)
        await EventPublisher.publish(
            type: "job.analysed",
            payload: ["job_id": jobId.uuidString],
            application: application,
            database: database,
            logger: logger
        )
        await EventPublisher.publish(
            type: needsReview ? "job.needs_review" : "job.completed",
            payload: ["job_id": jobId.uuidString],
            application: application,
            database: database,
            logger: logger
        )

        if needsReview {
            logger.info("Tâche marquee en revue requise.", metadata: [
                "job_id": .string(jobId.uuidString),
                "confidence": .string("\(analysis.confidence)"),
                "threshold": .string("\(confidenceThreshold)"),
                "review_reasons": .string((analysis.review?.reasons ?? []).joined(separator: ","))
            ])
            return updatedJob
        }

        do {
            _ = try await autoRouteIfRequested(
                job: updatedJob,
                application: application,
                database: database,
                logger: logger
            )
        } catch {
            logger.error("Échec du routage automatique après analyse.", metadata: [
                "job_id": .string(jobId.uuidString),
                "error": .string(error.localizedDescription)
            ])
            if let flagged = await application.appState.flagNeedsReview(
                jobId: jobId,
                reason: "auto_route_failed"
            ) {
                try await JobPersistenceRepository.upsert(job: flagged, on: database)
                await EventPublisher.publish(
                    type: "job.needs_review",
                    payload: [
                        "job_id": jobId.uuidString,
                        "reason": "auto_route_failed"
                    ],
                    application: application,
                    database: database,
                    logger: logger
                )
                return flagged
            }
        }
        return updatedJob
    }
}
