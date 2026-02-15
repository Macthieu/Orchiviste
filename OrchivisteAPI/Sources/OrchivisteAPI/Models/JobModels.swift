import Vapor

enum JobStatus: String, Content, Codable {
    case pending
    case running
    case needs_review
    case completed
    case failed
    case cancelled
}

struct JobStepTimestamps: Content, Codable {
    var ingestReceived: Date?
    var previewReady: Date?
    var analysed: Date?
    var routed: Date?
    var completed: Date?
}

struct JobSource: Content, Codable {
    var kind: String
    var url: String?
    var site: String?
    var library: String?
    var itemId: String?
}

struct JobRecord: Content, Codable {
    let id: UUID
    var status: JobStatus
    var fileURL: String
    var source: JobSource
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var steps: JobStepTimestamps
    var suggestedPreset: String?
    var suggestedClassCode: String?
    var confidence: Double?
    var needsReview: Bool
}

struct JobCancelResponse: Content {
    let id: UUID
    let status: JobStatus
}
