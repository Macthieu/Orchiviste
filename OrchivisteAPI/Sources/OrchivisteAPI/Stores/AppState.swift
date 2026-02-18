import Vapor

struct IdempotencyEntry: Sendable {
    let jobId: UUID
    let requestHash: String
}

actor AppState {
    private var jobs: [UUID: JobRecord] = [:]
    private var previews: [UUID: PreviewRecord] = [:]
    private var analyses: [UUID: AnalysisResponse] = [:]
    private var presets: [String: Preset] = [:]
    private var agendas: [String: AgendaRecord] = [:]
    private var taxonomies: [String: TaxonomyRecord] = [:]
    private var workers: [UUID: WorkerRecord] = [:]
    private var events: [EventRecord] = []
    private var nextEventId: Int = 1
    private var idempotency: [String: IdempotencyEntry] = [:]

    func idempotencyEntry(for idempotencyKey: String?) -> IdempotencyEntry? {
        guard let idempotencyKey else { return nil }
        return idempotency[idempotencyKey]
    }

    func rememberIdempotency(_ key: String, requestHash: String, jobId: UUID) {
        idempotency[key] = IdempotencyEntry(jobId: jobId, requestHash: requestHash)
    }

    func createJob(fileURL: String, source: JobSource, tags: [String]) -> JobRecord {
        let now = Date()
        let job = JobRecord(
            id: UUID(),
            status: .pending,
            fileURL: fileURL,
            source: source,
            tags: tags,
            createdAt: now,
            updatedAt: now,
            steps: JobStepTimestamps(ingestReceived: now, previewReady: nil, analysed: nil, routed: nil, completed: nil),
            suggestedPreset: nil,
            suggestedClassCode: nil,
            confidence: nil,
            needsReview: false
        )
        jobs[job.id] = job
        addEvent(type: "job.ingest_received", payload: ["job_id": job.id.uuidString])
        return job
    }

    func cacheJob(_ job: JobRecord) {
        jobs[job.id] = job
    }

    func job(id: UUID) -> JobRecord? {
        jobs[id]
    }

    func listJobs(limit: Int = 100) -> [JobRecord] {
        let bounded = max(1, min(500, limit))
        return jobs.values
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(bounded)
            .map { $0 }
    }

    func cancelJob(id: UUID) -> JobRecord? {
        guard var job = jobs[id] else { return nil }
        job.status = .cancelled
        job.updatedAt = Date()
        job.steps.completed = job.steps.completed ?? Date()
        jobs[id] = job
        addEvent(type: "job.cancelled", payload: ["job_id": id.uuidString])
        return job
    }

    func failJob(id: UUID) -> JobRecord? {
        guard var job = jobs[id] else { return nil }
        let now = Date()
        job.status = .failed
        job.updatedAt = now
        job.steps.completed = job.steps.completed ?? now
        jobs[id] = job
        addEvent(type: "job.failed", payload: ["job_id": id.uuidString])
        return job
    }

    func markPreviewReady(jobId: UUID, preview: PreviewRecord) -> JobRecord? {
        previews[jobId] = preview
        guard var job = jobs[jobId] else { return nil }
        job.status = .running
        job.updatedAt = Date()
        job.steps.previewReady = preview.createdAt
        jobs[jobId] = job
        addEvent(type: "job.preview_ready", payload: ["job_id": jobId.uuidString])
        return job
    }

    func attachAnalysis(jobId: UUID, analysis: AnalysisResponse, needsReview: Bool) -> JobRecord? {
        analyses[jobId] = analysis
        guard var job = jobs[jobId] else { return nil }
        job.updatedAt = Date()
        job.steps.analysed = Date()
        job.suggestedPreset = analysis.suggested_preset
        job.suggestedClassCode = analysis.suggested_class_code
        job.confidence = analysis.confidence
        job.needsReview = needsReview
        job.status = needsReview ? .needs_review : .completed
        if job.status == .completed {
            job.steps.completed = Date()
        }
        jobs[jobId] = job
        addEvent(type: "job.analysed", payload: ["job_id": jobId.uuidString])
        if needsReview {
            addEvent(type: "job.needs_review", payload: ["job_id": jobId.uuidString])
        } else {
            addEvent(type: "job.completed", payload: ["job_id": jobId.uuidString])
        }
        return job
    }

    func markRouted(jobId: UUID, classCode: String?) -> JobRecord? {
        guard var job = jobs[jobId] else { return nil }
        let now = Date()
        job.updatedAt = now
        job.steps.routed = now
        if let classCode, !classCode.isEmpty {
            job.suggestedClassCode = classCode
        }
        if job.status != .cancelled && job.status != .failed && job.status != .needs_review {
            job.status = .completed
            job.steps.completed = job.steps.completed ?? now
        }
        jobs[jobId] = job
        addEvent(type: "job.routed", payload: ["job_id": jobId.uuidString])
        return job
    }

    func applyReview(jobId: UUID, request: JobReviewRequest) -> JobRecord? {
        guard var job = jobs[jobId] else { return nil }
        let now = Date()
        job.updatedAt = now
        job.needsReview = false
        job.status = .completed
        job.steps.completed = job.steps.completed ?? now
        if let correctedClassCode = request.corrected_class_code, !correctedClassCode.isEmpty {
            job.suggestedClassCode = correctedClassCode
        }
        if let correctedPreset = request.corrected_preset, !correctedPreset.isEmpty {
            job.suggestedPreset = correctedPreset
        }
        jobs[jobId] = job
        addEvent(type: "job.reviewed", payload: ["job_id": jobId.uuidString])
        addEvent(type: "job.completed", payload: ["job_id": jobId.uuidString])
        return job
    }

    func preview(jobId: UUID) -> PreviewRecord? {
        previews[jobId]
    }

    func analysis(jobId: UUID) -> AnalysisResponse? {
        analyses[jobId]
    }

    func listPresets() -> [Preset] {
        Array(presets.values)
    }

    func upsertPreset(_ preset: Preset) {
        presets[preset.id] = preset
        addEvent(type: "preset.saved", payload: ["preset_id": preset.id])
    }

    func saveAgenda(_ agenda: AgendaRecord) {
        agendas[agenda.session_id] = agenda
        addEvent(type: "agenda.saved", payload: ["session_id": agenda.session_id])
    }

    func agenda(sessionId: String) -> AgendaRecord? {
        agendas[sessionId]
    }

    func saveTaxonomy(_ taxonomy: TaxonomyRecord) {
        taxonomies[taxonomy.taxonomy_id] = taxonomy
        addEvent(type: "taxonomy.saved", payload: ["taxonomy_id": taxonomy.taxonomy_id])
    }

    func taxonomy(id: String) -> TaxonomyRecord? {
        taxonomies[id]
    }

    func listTaxonomies() -> [TaxonomyRecord] {
        Array(taxonomies.values)
    }

    func enrollWorker(name: String, capabilities: [String]) -> WorkerRecord {
        let worker = WorkerRecord(
            id: UUID(),
            name: name,
            status: .pending,
            capabilities: capabilities,
            lastSeen: nil,
            version: nil,
            load: nil,
            ram_mb: nil,
            token: nil
        )
        workers[worker.id] = worker
        addEvent(type: "worker.enrolled", payload: ["worker_id": worker.id.uuidString])
        return worker
    }

    func approveWorker(id: UUID) -> WorkerRecord? {
        guard var worker = workers[id] else { return nil }
        worker.status = .approved
        worker.token = worker.token ?? UUID().uuidString
        workers[id] = worker
        addEvent(type: "worker.approved", payload: ["worker_id": id.uuidString])
        return worker
    }

    func worker(id: UUID) -> WorkerRecord? {
        workers[id]
    }

    func cacheWorker(_ worker: WorkerRecord) {
        workers[worker.id] = worker
    }

    func cacheWorkers(_ records: [WorkerRecord]) {
        for worker in records {
            workers[worker.id] = worker
        }
    }

    func heartbeatWorker(id: UUID, payload: WorkerHeartbeatRequest) -> WorkerRecord? {
        guard var worker = workers[id] else { return nil }
        worker.lastSeen = Date()
        worker.version = payload.version ?? worker.version
        worker.load = payload.load ?? worker.load
        worker.ram_mb = payload.ram_mb ?? worker.ram_mb
        if let caps = payload.capabilities {
            worker.capabilities = caps
        }
        workers[id] = worker
        addEvent(type: "worker.heartbeat", payload: ["worker_id": id.uuidString])
        return worker
    }

    func listWorkers() -> [WorkerRecord] {
        Array(workers.values)
    }

    func addEvent(type: String, payload: [String: String]) {
        let event = EventRecord(id: nextEventId, type: type, created_at: Date(), payload: payload)
        nextEventId += 1
        events.append(event)
        if events.count > 5000 {
            events.removeFirst(events.count - 5000)
        }
    }

    func events(after cursor: Int) -> EventsResponse {
        let filtered = events.filter { $0.id > cursor }
        let newCursor = filtered.last?.id ?? cursor
        return EventsResponse(cursor: newCursor, events: filtered)
    }
}

extension Application {
    private struct AppStateKey: StorageKey {
        typealias Value = AppState
    }

    var appState: AppState {
        if let existing = storage[AppStateKey.self] {
            return existing
        }
        let state = AppState()
        storage[AppStateKey.self] = state
        return state
    }
}
