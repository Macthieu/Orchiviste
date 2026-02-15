import Foundation
@testable import OrchivisteAPI

enum OrchivisteAPITestsPlaceholder {
    // Kept intentionally lightweight because XCTest is unavailable in this environment.
    static let migrations: [Any] = [
        CreateJobsMigration(),
        CreateEventsMigration(),
        CreateIdempotencyKeysMigration()
    ]

    static let sampleJob = JobRecord(
        id: UUID(),
        status: .pending,
        fileURL: "/tmp/sample.pdf",
        source: JobSource(kind: "local", url: nil, site: nil, library: nil, itemId: nil),
        tags: ["smoke"],
        createdAt: Date(),
        updatedAt: Date(),
        steps: JobStepTimestamps(
            ingestReceived: Date(),
            previewReady: nil,
            analysed: nil,
            routed: nil,
            completed: nil
        ),
        suggestedPreset: nil,
        suggestedClassCode: nil,
        confidence: nil,
        needsReview: false
    )
}
