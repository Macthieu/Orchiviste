import Foundation

public struct IngestJob: Codable {
    public let taskId: UUID
    public let fileURL: String
    public let source: String
    public let tags: [String]?
    public let enqueuedAt: Date

    public init(
        taskId: UUID,
        fileURL: String,
        source: String,
        tags: [String]?,
        enqueuedAt: Date
    ) {
        self.taskId = taskId
        self.fileURL = fileURL
        self.source = source
        self.tags = tags
        self.enqueuedAt = enqueuedAt
    }
}
