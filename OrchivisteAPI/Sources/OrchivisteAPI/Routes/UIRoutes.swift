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
    let upload_error: String?
}

private struct UIJobsContext: Encodable {
    let jobs: [UIJobSummary]
}

private struct UIWorkersContext: Encodable {
    let workers: [UIWorkerSummary]
    let queue_ingest_depth: Int
    let queue_dead_letter_depth: Int
    let notice: String?
    let error: String?
}

private struct UIPresetsContext: Encodable {
    let presets: [UIPresetSummary]
    let notice: String?
    let error: String?
}

private struct UIEventsContext: Encodable {
    let events: [UIEventSummary]
    let initial_cursor: Int
}

private struct UIEventSummary: Encodable {
    let id: Int
    let type: String
    let created_at: String
    let payload: String
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
    let status_raw: String
    let status: String
    let capabilities: String
    let last_seen: String
    let version: String
    let load: String
    let ram_mb: String
    let can_approve: Bool
    let can_heartbeat: Bool
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

private struct UILocalIngestForm: Content {
    let pdf: File
    let tags: String?
}

private struct UIPresetCreateForm: Content {
    let id: String
    let name: String
    let name_format: String
    let class_code: String?
    let postprocess: String?
}

private struct UIWorkerEnrollForm: Content {
    let name: String
    let capabilities: String?
}

private struct UIWorkerHeartbeatForm: Content {
    let version: String?
    let load: String?
    let ram_mb: String?
    let capabilities: String?
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
    app.get("u", "events") { req async throws -> Response in
        req.redirect(to: "/ui/events")
    }
    app.get("u", "jobs", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id") else {
            return req.redirect(to: "/ui/jobs")
        }
        return req.redirect(to: "/ui/jobs/\(id)")
    }

    app.on(.POST, "ui", "ingest", "local", body: .collect(maxSize: "48mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UILocalIngestForm.self)
            let filename = form.pdf.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filename.isEmpty else {
                throw Abort(.badRequest, reason: "Aucun fichier fourni.")
            }
            guard filename.lowercased().hasSuffix(".pdf") else {
                throw Abort(.badRequest, reason: "Seuls les fichiers PDF sont acceptés.")
            }
            guard form.pdf.data.readableBytes > 0 else {
                throw Abort(.badRequest, reason: "Le fichier PDF est vide.")
            }

            let inboxDirectory = resolveUILocalIngestInboxDirectory()
            try FileManager.default.createDirectory(
                at: inboxDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let safeName = sanitizeUploadFileName(filename)
            let timestamp = formatUploadTimestamp(Date())
            let destination = inboxDirectory.appendingPathComponent("\(timestamp)-\(safeName)")
            try Data(buffer: form.pdf.data).write(to: destination, options: .atomic)

            let parsedTags = parseUploadTags(raw: form.tags)
            let requestBody = IngestRequest(
                fileURL: destination.path,
                source: JobSource(kind: "local", url: nil, site: nil, library: nil, itemId: nil),
                tags: parsedTags.isEmpty ? nil : parsedTags,
                hints: nil
            )
            let taskId = try await enqueueIngest(
                body: requestBody,
                idempotencyKey: "ui-upload-\(UUID().uuidString)",
                req: req
            )
            return req.redirect(to: "/ui/jobs/\(taskId.uuidString)")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec de l'import PDF." : abort.reason
            req.logger.warning("Échec ingestion UI.", metadata: [
                "reason": .string(reason)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec ingestion UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded("Erreur interne pendant l'import PDF."))")
        }
    }

    app.on(.POST, "ui", "presets", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIPresetCreateForm.self)
            let preset = Preset(
                id: form.id.trimmingCharacters(in: .whitespacesAndNewlines),
                name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
                name_format: form.name_format.trimmingCharacters(in: .whitespacesAndNewlines),
                class_code: nonEmptyString(form.class_code),
                postprocess: parseUploadTags(raw: form.postprocess)
            )
            try validatePreset(preset)
            await req.application.appState.upsertPreset(preset)
            try ConfigLoader.savePreset(preset)
            return req.redirect(to: "/ui/presets?notice=\(urlQueryEncoded("Préréglage enregistré."))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec de création du préréglage." : abort.reason
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec création préréglage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant la création du préréglage."))")
        }
    }

    app.on(.POST, "ui", "workers", "enroll", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIWorkerEnrollForm.self)
            let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw Abort(.badRequest, reason: "Le nom de l'agent est requis.")
            }
            let capabilities = parseUploadTags(raw: form.capabilities)
            let worker = await req.application.appState.enrollWorker(
                name: name,
                capabilities: capabilities
            )
            await EventPublisher.publish(
                type: "worker.enrolled",
                payload: ["worker_id": worker.id.uuidString],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Agent enrôlé."))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded(abort.reason))")
        } catch {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Erreur interne pendant l'enrôlement."))")
        }
    }

    app.post("ui", "workers", ":id", "approve") { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let workerID = UUID(uuidString: id) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Identifiant d'agent invalide."))")
        }
        guard let worker = await req.application.appState.approveWorker(id: workerID) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }
        await EventPublisher.publish(
            type: "worker.approved",
            payload: ["worker_id": worker.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Agent approuvé."))")
    }

    app.on(.POST, "ui", "workers", ":id", "heartbeat", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let workerID = UUID(uuidString: id) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Identifiant d'agent invalide."))")
        }
        guard let existing = await req.application.appState.worker(id: workerID) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }
        guard existing.status == .approved else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("L'agent doit être approuvé avant heartbeat."))")
        }

        let form = try req.content.decode(UIWorkerHeartbeatForm.self)
        let heartbeat = WorkerHeartbeatRequest(
            version: nonEmptyString(form.version) ?? "ui-test",
            load: parseOptionalDouble(form.load),
            ram_mb: parseOptionalInt(form.ram_mb),
            capabilities: {
                let parsed = parseUploadTags(raw: form.capabilities)
                return parsed.isEmpty ? nil : parsed
            }()
        )

        guard let worker = await req.application.appState.heartbeatWorker(id: workerID, payload: heartbeat) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }
        await EventPublisher.publish(
            type: "worker.heartbeat",
            payload: ["worker_id": worker.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Heartbeat de test envoyé."))")
    }

    app.get("ui") { req async throws -> View in
        let jobs = try await loadJobs(req: req, limit: 100)
        let workerCount = await req.application.appState.listWorkers().count
        let queueStats = await RedisQueueService.queueStats(application: req.application, logger: req.logger)
        let uploadError = req.query[String.self, at: "upload_error"]

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
            recent_jobs: Array(jobs.prefix(15)),
            upload_error: uploadError
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
            queue_dead_letter_depth: queueStats.dead_letter_depth,
            notice: req.query[String.self, at: "notice"],
            error: req.query[String.self, at: "error"]
        )
        return try await req.view.render("workers", context)
    }

    app.get("ui", "presets") { req async throws -> View in
        let presets = await loadPresets(req: req)
        return try await req.view.render(
            "presets",
            UIPresetsContext(
                presets: presets,
                notice: req.query[String.self, at: "notice"],
                error: req.query[String.self, at: "error"]
            )
        )
    }

    app.get("ui", "events") { req async throws -> View in
        let bootstrap = try await loadUIEvents(req: req, cursor: 0)
        let summaries = bootstrap.events.map { event in
            UIEventSummary(
                id: event.id,
                type: event.type,
                created_at: formatTimestamp(event.created_at),
                payload: formatEventPayload(event.payload)
            )
        }
        let context = UIEventsContext(
            events: Array(summaries.suffix(200)),
            initial_cursor: bootstrap.cursor
        )
        return try await req.view.render("events", context)
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
        let rawStatus = worker.status.rawValue
        return UIWorkerSummary(
            id: worker.id.uuidString,
            name: worker.name,
            status_raw: rawStatus,
            status: localizedWorkerStatus(rawStatus),
            capabilities: worker.capabilities.joined(separator: ", "),
            last_seen: worker.lastSeen.map(formatTimestamp) ?? "-",
            version: worker.version ?? "-",
            load: worker.load.map { String(format: "%.2f", $0) } ?? "-",
            ram_mb: worker.ram_mb.map(String.init) ?? "-",
            can_approve: rawStatus == WorkerStatus.pending.rawValue,
            can_heartbeat: rawStatus == WorkerStatus.approved.rawValue
        )
    }
}

private func loadUIEvents(req: Request, cursor: Int) async throws -> EventsResponse {
    do {
        return try await JobPersistenceRepository.listEvents(after: cursor, on: req.db)
    } catch {
        req.logger.warning("Bascule vers les événements en mémoire: \(error.localizedDescription)")
        return await req.application.appState.events(after: cursor)
    }
}

private func loadPresets(req: Request) async -> [UIPresetSummary] {
    let disk = ConfigLoader.loadPresets()
    let memory = await req.application.appState.listPresets()
    return mergePresets(disk: disk, memory: memory)
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

private func formatEventPayload(_ payload: [String: String]) -> String {
    guard !payload.isEmpty else { return "-" }
    return payload
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")
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

private func parseUploadTags(raw: String?) -> [String] {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return []
    }
    return raw
        .split(whereSeparator: { $0 == "," || $0 == ";" })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func nonEmptyString(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func parseOptionalDouble(_ raw: String?) -> Double? {
    guard let value = nonEmptyString(raw) else { return nil }
    return Double(value)
}

private func parseOptionalInt(_ raw: String?) -> Int? {
    guard let value = nonEmptyString(raw) else { return nil }
    return Int(value)
}

private func resolveUILocalIngestInboxDirectory() -> URL {
    if let configured = Environment.get("ORCHIVISTE_LOCAL_INGEST_ROOT")?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !configured.isEmpty {
        return URL(fileURLWithPath: configured, isDirectory: true)
    }

    if let sqlitePath = Environment.get("ORCHIVISTE_SQLITE_PATH"),
       sqlitePath.hasPrefix("/") {
        return URL(fileURLWithPath: sqlitePath)
            .deletingLastPathComponent()
            .appendingPathComponent("inbox", isDirectory: true)
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".orchiviste-inbox", isDirectory: true)
}

private func sanitizeUploadFileName(_ raw: String) -> String {
    let filename = (raw as NSString).lastPathComponent
    let allowed = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "._-"))
    let sanitized = filename.unicodeScalars
        .map { allowed.contains($0) ? Character($0) : "_" }
        .reduce(into: "") { partialResult, next in
            partialResult.append(next)
        }
    let fallback = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    if fallback.isEmpty {
        return "document.pdf"
    }
    return fallback
}

private func formatUploadTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
}

private func urlQueryEncoded(_ raw: String) -> String {
    raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
}
