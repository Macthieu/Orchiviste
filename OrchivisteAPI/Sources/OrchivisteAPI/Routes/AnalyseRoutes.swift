import Vapor

func registerAnalyseRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("analyse") { req async throws -> AnalysisResponse in
            let body = try req.content.decode(AnalysisRequest.self)
            let correlationId = req.headers.first(name: "x-correlation-id")

            let response = await AnalysisProxyClient.analyzeWithFallback(
                request: body,
                correlationId: correlationId,
                using: req.client,
                logger: req.logger
            )

            _ = try await JobAnalysisLifecycle.apply(
                analysis: response,
                forFileID: body.file_id,
                policy: body.policy,
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return response
        }
    }
}
