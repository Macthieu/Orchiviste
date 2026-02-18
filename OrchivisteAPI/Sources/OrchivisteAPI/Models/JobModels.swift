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
    var analysisTypeDoc: String?
    var analysisSujets: [String]?
    var analysisChamps: [String: String]?
    var confidence: Double?
    var needsReview: Bool
}

struct JobCancelResponse: Content {
    let id: UUID
    let status: JobStatus
}

struct JobReviewRequest: Content {
    let corrected_fields: [String: String]?
    let corrected_class_code: String?
    let corrected_preset: String?
    let comment: String?
}
