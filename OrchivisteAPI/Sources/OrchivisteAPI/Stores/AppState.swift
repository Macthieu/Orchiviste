import Vapor

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
    private var idempotency: [String: UUID] = [:]

    func getOrCreateJobId(for idempotencyKey: String?) -> UUID? {
        guard let idempotencyKey else { return nil }
        return idempotency[idempotencyKey]
    }

    func rememberIdempotency(_ key: String, jobId: UUID) {
        idempotency[key] = jobId
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
        addEvent(type: "job.created", payload: ["job_id": job.id.uuidString])
        return job
    }

    func job(id: UUID) -> JobRecord? {
        jobs[id]
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

    func markPreviewReady(jobId: UUID, preview: PreviewRecord) {
        previews[jobId] = preview
        guard var job = jobs[jobId] else { return }
        job.status = .running
        job.updatedAt = Date()
        job.steps.previewReady = preview.createdAt
        jobs[jobId] = job
        addEvent(type: "preview.ready", payload: ["job_id": jobId.uuidString])
    }

    func attachAnalysis(jobId: UUID, analysis: AnalysisResponse, needsReview: Bool) {
        analyses[jobId] = analysis
        guard var job = jobs[jobId] else { return }
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
        addEvent(type: "analysis.completed", payload: ["job_id": jobId.uuidString])
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
