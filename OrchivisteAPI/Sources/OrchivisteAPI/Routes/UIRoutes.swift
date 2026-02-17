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

private struct UIWorkersContext: Encodable {
    let workers: [UIWorkerSummary]
    let queue_ingest_depth: Int
    let queue_dead_letter_depth: Int
}

private struct UIPresetsContext: Encodable {
    let presets: [UIPresetSummary]
}

private struct UIJobSummary: Encodable {
    let id: String
    let status: String
    let status_label: String
    let file_url: String
    let source_kind: String
    let confidence: String
    let suggested_class_code: String
    let updated_at: String
}

private struct UIWorkerSummary: Encodable {
    let id: String
    let name: String
    let status: String
    let capabilities: String
    let last_seen: String
    let version: String
    let load: String
    let ram_mb: String
}

private struct UIPresetSummary: Encodable {
    let id: String
    let name: String
    let name_format: String
    let class_code: String
    let postprocess: String
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
    let can_route: Bool
    let route_disabled_reason: String?
    let routed_at: String?
    let preview_pages: Int
    let download_url: String
}

func registerUIRoutes(_ app: Application) {
    app.get { req async throws -> Response in
        req.redirect(to: "/ui")
    }

    app.get("u") { req async throws -> Response in
        req.redirect(to: "/ui")
    }
    app.get("u", "jobs") { req async throws -> Response in
        req.redirect(to: "/ui/jobs")
    }
    app.get("u", "workers") { req async throws -> Response in
        req.redirect(to: "/ui/workers")
    }
    app.get("u", "presets") { req async throws -> Response in
        req.redirect(to: "/ui/presets")
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

    app.get("ui", "workers") { req async throws -> View in
        let workers = await loadWorkers(req: req)
        let queueStats = await RedisQueueService.queueStats(application: req.application, logger: req.logger)
        let context = UIWorkersContext(
            workers: workers,
            queue_ingest_depth: queueStats.ingest_depth,
            queue_dead_letter_depth: queueStats.dead_letter_depth
        )
        return try await req.view.render("workers", context)
    }

    app.get("ui", "presets") { req async throws -> View in
        let presets = await loadPresets(req: req)
        return try await req.view.render("presets", UIPresetsContext(presets: presets))
    }

    app.get("ui", "jobs", ":id") { req async throws -> View in
        guard let id = req.parameters.get("id"),
              let jobID = UUID(uuidString: id) else {
            throw Abort(.badRequest, reason: "Identifiant de tâche invalide.")
        }
        let job = try await resolveUIJob(jobID: jobID, req: req)
        let preview = await req.application.appState.preview(jobId: jobID)
        let canRoute: Bool
        let routeDisabledReason: String?
        if job.status == .needs_review {
            canRoute = false
            routeDisabledReason = "Revue requise avant routage."
        } else if job.status == .pending || job.status == .running {
            canRoute = false
            routeDisabledReason = "Analyse en cours."
        } else if job.status == .failed || job.status == .cancelled {
            canRoute = false
            routeDisabledReason = "Statut non routable."
        } else if job.steps.routed != nil {
            canRoute = false
            routeDisabledReason = "Cette tâche est déjà routée."
        } else {
            canRoute = true
            routeDisabledReason = nil
        }
        let context = UIJobViewerContext(
            id: job.id.uuidString,
            status: localizedJobStatus(job.status.rawValue),
            file_url: job.fileURL,
            source_kind: localizedSourceKind(job.source.kind),
            suggested_preset: job.suggestedPreset ?? "N/D",
            suggested_class_code: job.suggestedClassCode ?? "N/D",
            confidence: job.confidence.map { String(format: "%.2f", $0) } ?? "-",
            needs_review: job.needsReview,
            can_review: job.status == .needs_review,
            can_route: canRoute,
            route_disabled_reason: routeDisabledReason,
            routed_at: job.steps.routed.map(formatTimestamp),
            preview_pages: max(1, preview?.pages ?? 1),
            download_url: "/v1/jobs/\(job.id.uuidString)/download"
        )
        return try await req.view.render("job_viewer", context)
    }
}

private func loadWorkers(req: Request) async -> [UIWorkerSummary] {
    let workers = await req.application.appState.listWorkers()
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    return workers.map { worker in
        UIWorkerSummary(
            id: worker.id.uuidString,
            name: worker.name,
            status: localizedWorkerStatus(worker.status.rawValue),
            capabilities: worker.capabilities.joined(separator: ", "),
            last_seen: worker.lastSeen.map(formatTimestamp) ?? "-",
            version: worker.version ?? "-",
            load: worker.load.map { String(format: "%.2f", $0) } ?? "-",
            ram_mb: worker.ram_mb.map(String.init) ?? "-"
        )
    }
}

private func loadPresets(req: Request) async -> [UIPresetSummary] {
    let disk = ConfigLoader.loadPresets()
    let memory = await req.application.appState.listPresets()
    let merged = Dictionary(uniqueKeysWithValues: (disk + memory).map { ($0.id, $0) })
    return merged.values
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        .map { preset in
            UIPresetSummary(
                id: preset.id,
                name: preset.name,
                name_format: preset.name_format,
                class_code: preset.class_code ?? "-",
                postprocess: (preset.postprocess ?? []).joined(separator: ", ")
            )
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
            status_label: localizedJobStatus(job.status.rawValue),
            file_url: job.fileURL,
            source_kind: localizedSourceKind(job.source.kind),
            confidence: job.confidence.map { String(format: "%.2f", $0) } ?? "-",
            suggested_class_code: job.suggestedClassCode ?? "N/D",
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
    throw Abort(.notFound, reason: "Tâche introuvable.")
}

private func formatTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func localizedJobStatus(_ raw: String) -> String {
    switch raw {
    case "pending": return "En attente"
    case "running": return "En cours"
    case "needs_review": return "Revue requise"
    case "completed": return "Terminée"
    case "failed": return "En échec"
    case "cancelled": return "Annulée"
    default: return raw
    }
}

private func localizedWorkerStatus(_ raw: String) -> String {
    switch raw {
    case "pending": return "En attente"
    case "approved": return "Approuvé"
    default: return raw
    }
}

private func localizedSourceKind(_ raw: String) -> String {
    switch raw.lowercased() {
    case "local": return "Local"
    case "sharepoint": return "SharePoint"
    default: return raw
    }
}
