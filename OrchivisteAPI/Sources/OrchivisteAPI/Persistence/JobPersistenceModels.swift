import Fluent
import Foundation

final class JobRow: Model, @unchecked Sendable {
    static let schema = "jobs"

    @ID(custom: "id", generatedBy: .user)
    var id: UUID?

    @Field(key: "status")
    var status: String

    @Field(key: "file_url")
    var fileURL: String

    @Field(key: "source_kind")
    var sourceKind: String

    @OptionalField(key: "source_url")
    var sourceURL: String?

    @OptionalField(key: "source_site")
    var sourceSite: String?

    @OptionalField(key: "source_library")
    var sourceLibrary: String?

    @OptionalField(key: "source_item_id")
    var sourceItemID: String?

    @Field(key: "tags_json")
    var tagsJSON: String

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "updated_at")
    var updatedAt: Date

    @OptionalField(key: "ingest_received_at")
    var ingestReceivedAt: Date?

    @OptionalField(key: "preview_ready_at")
    var previewReadyAt: Date?

    @OptionalField(key: "analysed_at")
    var analysedAt: Date?

    @OptionalField(key: "routed_at")
    var routedAt: Date?

    @OptionalField(key: "completed_at")
    var completedAt: Date?

    @OptionalField(key: "suggested_preset")
    var suggestedPreset: String?

    @OptionalField(key: "suggested_class_code")
    var suggestedClassCode: String?

    @OptionalField(key: "confidence")
    var confidence: Double?

    @Field(key: "needs_review")
    var needsReview: Bool

    init() { }

    init(record: JobRecord, tagsJSON: String) {
        self.id = record.id
        self.status = record.status.rawValue
        self.fileURL = record.fileURL
        self.sourceKind = record.source.kind
        self.sourceURL = record.source.url
        self.sourceSite = record.source.site
        self.sourceLibrary = record.source.library
        self.sourceItemID = record.source.itemId
        self.tagsJSON = tagsJSON
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.ingestReceivedAt = record.steps.ingestReceived
        self.previewReadyAt = record.steps.previewReady
        self.analysedAt = record.steps.analysed
        self.routedAt = record.steps.routed
        self.completedAt = record.steps.completed
        self.suggestedPreset = record.suggestedPreset
        self.suggestedClassCode = record.suggestedClassCode
        self.confidence = record.confidence
        self.needsReview = record.needsReview
    }
}

final class EventRow: Model, @unchecked Sendable {
    static let schema = "events"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "type")
    var type: String

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "payload_json")
    var payloadJSON: String

    init() { }

    init(type: String, createdAt: Date, payloadJSON: String) {
        self.type = type
        self.createdAt = createdAt
        self.payloadJSON = payloadJSON
    }
}

final class IdempotencyKeyRow: Model, @unchecked Sendable {
    static let schema = "idempotency_keys"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "key")
    var key: String

    @Field(key: "request_hash")
    var requestHash: String

    @Field(key: "job_id")
    var jobID: UUID

    @Field(key: "created_at")
    var createdAt: Date

    init() { }

    init(key: String, requestHash: String, jobID: UUID, createdAt: Date) {
        self.key = key
        self.requestHash = requestHash
        self.jobID = jobID
        self.createdAt = createdAt
    }
}

struct PersistedIdempotencyRecord: Sendable {
    let key: String
    let requestHash: String
    let jobId: UUID
}
