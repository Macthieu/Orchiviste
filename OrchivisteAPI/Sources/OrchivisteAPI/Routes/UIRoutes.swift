import Foundation
import Vapor

private struct UIDashboardContext: Encodable {
    let total_jobs: Int
    let pending_jobs: Int
    let running_jobs: Int
    let needs_review_jobs: Int
    let completed_jobs: Int
    let failed_jobs: Int
    let cancelled_jobs: Int
    let worker_count: Int
    let queue_ingest_depth: Int
    let queue_dead_letter_depth: Int
    let recent_jobs: [UIJobSummary]
}

private struct UIJobsContext: Encodable {
    let jobs: [UIJobSummary]
}

private struct UIJobSummary: Encodable {
    let id: String
    let status: String
    let file_url: String
    let source_kind: String
    let confidence: String
    let suggested_class_code: String
    let updated_at: String
}

private struct UIJobViewerContext: Encodable {
    let id: String
    let status: String
    let file_url: String
    let source_kind: String
    let suggested_preset: String
    let suggested_class_code: String
    let confidence: String
    let needs_review: Bool
    let can_review: Bool
    let preview_pages: Int
    let download_url: String
}

func registerUIRoutes(_ app: Application) {
    app.get("u") { req async throws -> Response in
        req.redirect(to: "/ui")
    }
    app.get("u", "jobs") { req async throws -> Response in
        req.redirect(to: "/ui/jobs")
    }
    app.get("u", "jobs", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id") else {
            return req.redirect(to: "/ui/jobs")
        }
        return req.redirect(to: "/ui/jobs/\(id)")
    }

    app.get("ui") { req async throws -> View in
        let jobs = try await loadJobs(req: req, limit: 100)
        let workerCount = await req.application.appState.listWorkers().count
        let queueStats = await RedisQueueService.queueStats(application: req.application, logger: req.logger)

        let counts = Dictionary(grouping: jobs, by: \.status)
        let context = UIDashboardContext(
            total_jobs: jobs.count,
            pending_jobs: counts["pending"]?.count ?? 0,
            running_jobs: counts["running"]?.count ?? 0,
            needs_review_jobs: counts["needs_review"]?.count ?? 0,
            completed_jobs: counts["completed"]?.count ?? 0,
            failed_jobs: counts["failed"]?.count ?? 0,
            cancelled_jobs: counts["cancelled"]?.count ?? 0,
            worker_count: workerCount,
            queue_ingest_depth: queueStats.ingest_depth,
            queue_dead_letter_depth: queueStats.dead_letter_depth,
            recent_jobs: Array(jobs.prefix(15))
        )
        return try await req.view.render("dashboard", context)
    }

    app.get("ui", "jobs") { req async throws -> View in
        let jobs = try await loadJobs(req: req, limit: 300)
        return try await req.view.render("jobs", UIJobsContext(jobs: jobs))
    }

    app.get("ui", "jobs", ":id") { req async throws -> View in
        guard let id = req.parameters.get("id"),
              let jobID = UUID(uuidString: id) else {
            throw Abort(.badRequest, reason: "Invalid job id.")
        }
        let job = try await resolveUIJob(jobID: jobID, req: req)
        let preview = await req.application.appState.preview(jobId: jobID)
        let context = UIJobViewerContext(
            id: job.id.uuidString,
            status: job.status.rawValue,
            file_url: job.fileURL,
            source_kind: job.source.kind,
            suggested_preset: job.suggestedPreset ?? "N/A",
            suggested_class_code: job.suggestedClassCode ?? "N/A",
            confidence: job.confidence.map { String(format: "%.2f", $0) } ?? "-",
            needs_review: job.needsReview,
            can_review: job.status == .needs_review,
            preview_pages: max(1, preview?.pages ?? 1),
            download_url: "/v1/jobs/\(job.id.uuidString)/download"
        )
        return try await req.view.render("job_viewer", context)
    }
}

private func loadJobs(req: Request, limit: Int) async throws -> [UIJobSummary] {
    let jobs: [JobRecord]
    if let persisted = try? await JobPersistenceRepository.listJobs(limit: limit, on: req.db),
       !persisted.isEmpty {
        jobs = persisted
    } else {
        jobs = await req.application.appState.listJobs(limit: limit)
    }
    return jobs.map { job in
        UIJobSummary(
            id: job.id.uuidString,
            status: job.status.rawValue,
            file_url: job.fileURL,
            source_kind: job.source.kind,
            confidence: job.confidence.map { String(format: "%.2f", $0) } ?? "-",
            suggested_class_code: job.suggestedClassCode ?? "N/A",
            updated_at: formatTimestamp(job.updatedAt)
        )
    }
}

private func resolveUIJob(jobID: UUID, req: Request) async throws -> JobRecord {
    if let inMemory = await req.application.appState.job(id: jobID) {
        return inMemory
    }
    if let persisted = try await JobPersistenceRepository.fetchJob(id: jobID, on: req.db) {
        await req.application.appState.cacheJob(persisted)
        return persisted
    }
    throw Abort(.notFound, reason: "Job not found.")
}

private func formatTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
