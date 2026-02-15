import Vapor

func registerAnalyseRoutes(_ app: Application) {
    app.get("v1", "health") { _ in
        ["status": "ok"]
    }

    app.post("v1", "analyse") { req async throws -> AnalysisResponse in
        let body = try req.content.decode(AnalysisRequest.self)
        let result = await req.application.analysisFusionEngine.analyze(
            request: body,
            logger: req.logger
        )

        let threshold = body.policy?.min_confidence ?? 0.7
        if result.confidence < threshold {
            req.logger.info("Analysis below confidence threshold.", metadata: [
                "file_id": .string(body.file_id),
                "confidence": .string("\(result.confidence)"),
                "threshold": .string("\(threshold)")
            ])
        }
        return result
    }
}
