import Foundation
import Vapor

struct CorrelationIDMiddleware: AsyncMiddleware {
    private static let header = HTTPHeaders.Name("x-correlation-id")

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let correlationId = req.headers.first(name: Self.header) ?? UUID().uuidString
        req.headers.replaceOrAdd(name: Self.header, value: correlationId)
        req.logger[metadataKey: "correlation_id"] = .string(correlationId)

        let response = try await next.respond(to: req)
        response.headers.replaceOrAdd(name: Self.header, value: correlationId)
        return response
    }
}
