import Foundation
import Vapor

@main
struct Boot {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do {
            app.logger.logLevel = .info
            app.http.server.configuration.hostname = Environment.get("ORCHIVISTE_ANALYSE_HOST") ?? "127.0.0.1"
            app.http.server.configuration.port = Environment.get("ORCHIVISTE_ANALYSE_PORT")
                .flatMap(Int.init) ?? 28781

            app.middleware.use(AnalyseCorrelationIDMiddleware())
            app.middleware.use(RouteLoggingMiddleware(logLevel: .info))

            registerAnalyseRoutes(app)

            app.logger.info("OrchivisteAnalyse en écoute sur \(app.http.server.configuration.hostname):\(app.http.server.configuration.port)")
            try await app.execute()
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
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
                AppleCoreMLProvider(),
                EmbeddingSimilarityProvider(),
                AppleFoundationModelsProvider(),
                CoreMLProvider(),
                CoginovAPIProvider(),
                LLMFallbackProvider()
            ]
        )
        storage[AnalysisFusionEngineKey.self] = engine
        return engine
    }
}
