import Vapor

enum PreviewLoader {
    static func ensurePreview(
        jobId: UUID,
        req: Request
    ) async throws -> PreviewRecord? {
        if let existing = await req.application.appState.preview(jobId: jobId) {
            return existing
        }

        let inMemory = await req.application.appState.job(id: jobId)
        let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: req.db)
        guard let job = inMemory ?? persisted else {
            return nil
        }
        await req.application.appState.cacheJob(job)

        let preview = PreviewRenderer.makePreview(for: job, logger: req.logger)
        await req.application.appState.cachePreview(preview)
        return preview
    }
}
