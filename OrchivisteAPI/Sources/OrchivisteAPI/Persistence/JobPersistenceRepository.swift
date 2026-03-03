import Fluent
import Foundation
import Vapor

enum JobPersistenceRepository {
    static func upsert(job: JobRecord, on db: Database) async throws {
        let tagsJSON = try encodeJSONString(job.tags)
        let analysisSujetsJSON = try job.analysisSujets.map(encodeJSONString)
        let analysisChampsJSON = try job.analysisChamps.map(encodeJSONString)
        if let existing = try await JobRow.find(job.id, on: db) {
            existing.status = job.status.rawValue
            existing.fileURL = job.fileURL
            existing.sourceKind = job.source.kind
            existing.sourceURL = job.source.url
            existing.sourceSite = job.source.site
            existing.sourceLibrary = job.source.library
            existing.sourceItemID = job.source.itemId
            existing.tagsJSON = tagsJSON
            existing.createdAt = job.createdAt
            existing.updatedAt = job.updatedAt
            existing.ingestReceivedAt = job.steps.ingestReceived
            existing.previewReadyAt = job.steps.previewReady
            existing.analysedAt = job.steps.analysed
            existing.routedAt = job.steps.routed
            existing.completedAt = job.steps.completed
            existing.suggestedPreset = job.suggestedPreset
            existing.suggestedClassCode = job.suggestedClassCode
            existing.analysisTypeDoc = job.analysisTypeDoc
            existing.analysisSujetsJSON = analysisSujetsJSON
            existing.analysisChampsJSON = analysisChampsJSON
            existing.confidence = job.confidence
            existing.needsReview = job.needsReview
            try await existing.update(on: db)
            return
        }

        let row = JobRow(record: job, tagsJSON: tagsJSON)
        row.analysisSujetsJSON = analysisSujetsJSON
        row.analysisChampsJSON = analysisChampsJSON
        try await row.create(on: db)
    }

    static func fetchJob(id: UUID, on db: Database) async throws -> JobRecord? {
        guard let row = try await JobRow.find(id, on: db) else {
            return nil
        }
        return try jobRecord(from: row)
    }

    static func listJobs(limit: Int = 100, on db: Database) async throws -> [JobRecord] {
        let bounded = max(1, min(500, limit))
        let rows = try await JobRow.query(on: db)
            .sort(\.$createdAt, .descending)
            .limit(bounded)
            .all()
        return try rows.map { row in
            try jobRecord(from: row)
        }
    }

    static func deleteAllJobs(on db: Database) async throws {
        try await JobRow.query(on: db).delete()
    }

    static func deleteAllIdempotencyKeys(on db: Database) async throws {
        try await IdempotencyKeyRow.query(on: db).delete()
    }

    static func saveIdempotency(
        key: String,
        requestHash: String,
        jobId: UUID,
        on db: Database
    ) async throws {
        if let existing = try await IdempotencyKeyRow.query(on: db)
            .filter(\.$key == key)
            .first() {
            existing.requestHash = requestHash
            existing.jobID = jobId
            existing.createdAt = Date()
            try await existing.update(on: db)
            return
        }

        let row = IdempotencyKeyRow(
            key: key,
            requestHash: requestHash,
            jobID: jobId,
            createdAt: Date()
        )
        try await row.create(on: db)
    }

    static func fetchIdempotency(
        key: String,
        on db: Database
    ) async throws -> PersistedIdempotencyRecord? {
        guard let row = try await IdempotencyKeyRow.query(on: db)
            .filter(\.$key == key)
            .first() else {
            return nil
        }
        return PersistedIdempotencyRecord(
            key: row.key,
            requestHash: row.requestHash,
            jobId: row.jobID
        )
    }

    static func upsertWorker(
        _ worker: WorkerRecord,
        on db: Database
    ) async throws {
        let now = Date()
        let capabilitiesJSON = try encodeJSONString(worker.capabilities)
        if let existing = try await WorkerRow.find(worker.id, on: db) {
            existing.name = worker.name
            existing.status = worker.status.rawValue
            existing.capabilitiesJSON = capabilitiesJSON
            existing.lastSeenAt = worker.lastSeen
            existing.version = worker.version
            existing.load = worker.load
            existing.ramMB = worker.ram_mb
            existing.token = worker.token
            existing.updatedAt = now
            try await existing.update(on: db)
            return
        }

        let row = WorkerRow(
            record: worker,
            capabilitiesJSON: capabilitiesJSON,
            createdAt: now,
            updatedAt: now
        )
        try await row.create(on: db)
    }

    static func fetchWorker(id: UUID, on db: Database) async throws -> WorkerRecord? {
        guard let row = try await WorkerRow.find(id, on: db) else {
            return nil
        }
        return try workerRecord(from: row)
    }

    static func listWorkers(on db: Database) async throws -> [WorkerRecord] {
        let rows = try await WorkerRow.query(on: db)
            .sort(\.$name, .ascending)
            .all()
        return try rows.map(workerRecord(from:))
    }

    static func enrollWorker(
        name: String,
        capabilities: [String],
        on db: Database
    ) async throws -> WorkerRecord {
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
        try await upsertWorker(worker, on: db)
        return worker
    }

    static func approveWorker(id: UUID, on db: Database) async throws -> WorkerRecord? {
        guard let existing = try await fetchWorker(id: id, on: db) else {
            return nil
        }
        var approved = existing
        approved.status = .approved
        approved.token = approved.token ?? UUID().uuidString
        try await upsertWorker(approved, on: db)
        return approved
    }

    static func pauseWorker(id: UUID, on db: Database) async throws -> WorkerRecord? {
        guard let existing = try await fetchWorker(id: id, on: db) else {
            return nil
        }
        var paused = existing
        paused.status = .paused
        try await upsertWorker(paused, on: db)
        return paused
    }

    static func resumeWorker(id: UUID, on db: Database) async throws -> WorkerRecord? {
        guard let existing = try await fetchWorker(id: id, on: db) else {
            return nil
        }
        var resumed = existing
        resumed.status = .approved
        try await upsertWorker(resumed, on: db)
        return resumed
    }

    static func configureWorker(
        id: UUID,
        payload: WorkerConfigUpdateRequest,
        on db: Database
    ) async throws -> WorkerRecord? {
        guard let existing = try await fetchWorker(id: id, on: db) else {
            return nil
        }
        var configured = existing
        if let capabilities = payload.capabilities {
            configured.capabilities = capabilities
        }
        if let version = payload.version?.trimmingCharacters(in: .whitespacesAndNewlines),
           !version.isEmpty {
            configured.version = version
        }
        try await upsertWorker(configured, on: db)
        return configured
    }

    static func heartbeatWorker(
        id: UUID,
        payload: WorkerHeartbeatRequest,
        on db: Database
    ) async throws -> WorkerRecord? {
        guard let existing = try await fetchWorker(id: id, on: db) else {
            return nil
        }
        var updated = existing
        updated.lastSeen = Date()
        updated.version = payload.version ?? updated.version
        updated.load = payload.load ?? updated.load
        updated.ram_mb = payload.ram_mb ?? updated.ram_mb
        if let caps = payload.capabilities {
            updated.capabilities = caps
        }
        try await upsertWorker(updated, on: db)
        return updated
    }

    @discardableResult
    static func appendEvent(
        type: String,
        payload: [String: String],
        on db: Database
    ) async throws -> EventRecord {
        let row = EventRow(
            type: type,
            createdAt: Date(),
            payloadJSON: try encodeJSONString(payload)
        )
        try await row.create(on: db)
        let id = row.id ?? 0
        return EventRecord(id: id, type: row.type, created_at: row.createdAt, payload: payload)
    }

    static func listEvents(after cursor: Int, on db: Database) async throws -> EventsResponse {
        let rows = try await EventRow.query(on: db)
            .sort(\.$id, .ascending)
            .all()

        let filtered = rows.compactMap { row -> EventRecord? in
            guard let id = row.id, id > cursor else { return nil }
            let payload: [String: String] = (try? decodeJSONValue(row.payloadJSON)) ?? [:]
            return EventRecord(
                id: id,
                type: row.type,
                created_at: row.createdAt,
                payload: payload
            )
        }
        let newCursor = filtered.last?.id ?? cursor
        return EventsResponse(cursor: newCursor, events: filtered)
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Échec de l'encodage JSON.")
        }
        return text
    }

    private static func decodeJSONValue<T: Decodable>(_ string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw Abort(.internalServerError, reason: "Charge JSON invalide.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func jobRecord(from row: JobRow) throws -> JobRecord {
        let id = row.id ?? UUID()
        let tags: [String] = (try? decodeJSONValue(row.tagsJSON)) ?? []
        let analysisSujets: [String]? = row.analysisSujetsJSON.flatMap { try? decodeJSONValue($0) }
        let analysisChamps: [String: String]? = row.analysisChampsJSON.flatMap { try? decodeJSONValue($0) }
        let status = JobStatus(rawValue: row.status) ?? .pending
        return JobRecord(
            id: id,
            status: status,
            fileURL: row.fileURL,
            source: JobSource(
                kind: row.sourceKind,
                url: row.sourceURL,
                site: row.sourceSite,
                library: row.sourceLibrary,
                itemId: row.sourceItemID
            ),
            tags: tags,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            steps: JobStepTimestamps(
                ingestReceived: row.ingestReceivedAt,
                previewReady: row.previewReadyAt,
                analysed: row.analysedAt,
                routed: row.routedAt,
                completed: row.completedAt
            ),
            suggestedPreset: row.suggestedPreset,
            suggestedClassCode: row.suggestedClassCode,
            analysisTypeDoc: row.analysisTypeDoc,
            analysisSujets: analysisSujets,
            analysisChamps: analysisChamps,
            confidence: row.confidence,
            needsReview: row.needsReview
        )
    }

    private static func workerRecord(from row: WorkerRow) throws -> WorkerRecord {
        let id = row.id ?? UUID()
        let capabilities: [String] = (try? decodeJSONValue(row.capabilitiesJSON)) ?? []
        return WorkerRecord(
            id: id,
            name: row.name,
            status: WorkerStatus(rawValue: row.status) ?? .pending,
            capabilities: capabilities,
            lastSeen: row.lastSeenAt,
            version: row.version,
            load: row.load,
            ram_mb: row.ramMB,
            token: row.token
        )
    }
}
