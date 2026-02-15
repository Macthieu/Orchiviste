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
        let needsReview = analysis.confidence < confidenceThreshold
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
            logger.info("Job flagged as needs_review.", metadata: [
                "job_id": .string(jobId.uuidString),
                "confidence": .string("\(analysis.confidence)"),
                "threshold": .string("\(confidenceThreshold)")
            ])
        }
        return updatedJob
    }
}
