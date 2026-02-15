import Foundation
@testable import OrchivisteAPI

enum OrchivisteAPITestsPlaceholder {
    // XCTest is unavailable in this environment; functional checks are run via scripts/smoke_mvp.sh.
    static let migrations: [Any] = [
        CreateJobsMigration(),
        CreateEventsMigration(),
        CreateIdempotencyKeysMigration()
    ]

    static let webhookVector: String = {
        let body = Data(#"{"event":"test"}"#.utf8)
        return WebhookSignature.sign(
            secret: "secret",
            timestamp: "1700000000",
            body: body
        )
    }()

    static let idempotencyFingerprintPair: (String, String) = {
        let decoder = JSONDecoder()
        let requestA = try? decoder.decode(
            IngestRequest.self,
            from: Data(#"{"fileURL":"a.pdf","source":{"kind":"local"},"tags":["x","y"]}"#.utf8)
        )
        let requestB = try? decoder.decode(
            IngestRequest.self,
            from: Data(#"{"fileURL":"a.pdf","source":{"kind":"local"},"tags":["y","x"]}"#.utf8)
        )
        return (
            requestA?.idempotencyFingerprint() ?? "",
            requestB?.idempotencyFingerprint() ?? ""
        )
    }()
}
