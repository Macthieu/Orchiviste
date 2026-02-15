import Foundation
import Vapor

@main
struct Boot {
    static func main() throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = Application(env)
        defer { app.shutdown() }

        app.logger.logLevel = .info
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = Environment.get("ORCHIVISTE_ANALYSE_PORT")
            .flatMap(Int.init) ?? 18081

        app.middleware.use(AnalyseCorrelationIDMiddleware())
        app.middleware.use(RouteLoggingMiddleware(logLevel: .info))

        registerAnalyseRoutes(app)

        app.logger.info("OrchivisteAnalyse listening on \(app.http.server.configuration.hostname):\(app.http.server.configuration.port)")
        try app.run()
    }
}

struct AnalyseCorrelationIDMiddleware: AsyncMiddleware {
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

extension Application {
    private struct AnalysisFusionEngineKey: StorageKey {
        typealias Value = WeightedFusionEngine
    }

    var analysisFusionEngine: WeightedFusionEngine {
        if let existing = storage[AnalysisFusionEngineKey.self] {
            return existing
        }
        let engine = WeightedFusionEngine(
            providers: [
                LocalHeuristicsProvider(),
                CoreMLProvider(),
                CoginovAPIProvider(),
                LLMFallbackProvider()
            ]
        )
        storage[AnalysisFusionEngineKey.self] = engine
        return engine
    }
}
