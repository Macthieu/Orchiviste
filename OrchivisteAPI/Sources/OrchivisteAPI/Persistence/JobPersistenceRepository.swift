import Fluent
import Foundation
import Vapor

enum JobPersistenceRepository {
    static func upsert(job: JobRecord, on db: Database) async throws {
        let tagsJSON = try encodeJSONString(job.tags)
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
            existing.confidence = job.confidence
            existing.needsReview = job.needsReview
            try await existing.update(on: db)
            return
        }

        let row = JobRow(record: job, tagsJSON: tagsJSON)
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
            throw Abort(.internalServerError, reason: "Encoding failure.")
        }
        return text
    }

    private static func decodeJSONValue<T: Decodable>(_ string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw Abort(.internalServerError, reason: "Invalid JSON payload.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func jobRecord(from row: JobRow) throws -> JobRecord {
        let id = row.id ?? UUID()
        let tags: [String] = (try? decodeJSONValue(row.tagsJSON)) ?? []
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
            confidence: row.confidence,
            needsReview: row.needsReview
        )
    }
}
