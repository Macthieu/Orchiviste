import XCTest
@testable import OrchivisteSharedKit

final class OrchivisteSharedKitTests: XCTestCase {
    func testIngestJobCodableRoundTrip() throws {
        let job = IngestJob(
            taskId: UUID(),
            fileURL: "file:///tmp/example.pdf",
            source: "tests",
            tags: ["a", "b"],
            enqueuedAt: Date()
        )

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(IngestJob.self, from: data)

        XCTAssertEqual(decoded.taskId, job.taskId)
        XCTAssertEqual(decoded.fileURL, job.fileURL)
        XCTAssertEqual(decoded.source, job.source)
        XCTAssertEqual(decoded.tags ?? [], job.tags ?? [])
    }
}
