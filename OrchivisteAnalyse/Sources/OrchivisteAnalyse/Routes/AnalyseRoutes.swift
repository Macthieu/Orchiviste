import Vapor

func registerAnalyseRoutes(_ app: Application) {
    app.get("v1", "health") { _ in
        ["status": "ok"]
    }

    app.on(.POST, "v1", "analyse", body: .collect(maxSize: analysisRequestBodyLimit())) { req async throws -> AnalysisResponse in
        let body = try req.content.decode(AnalysisRequest.self)
        let baseResult = await req.application.analysisFusionEngine.analyze(
            request: body,
            logger: req.logger
        )

        let threshold = body.policy?.min_confidence ?? 0.7
        let result = applyPolicyReview(result: baseResult, threshold: threshold)
        if result.review?.needs_review == true {
            req.logger.info("Analyse sous le seuil de confiance.", metadata: [
                "file_id": .string(body.file_id),
                "confidence": .string("\(result.confidence)"),
                "threshold": .string("\(threshold)"),
                "review_reasons": .string((result.review?.reasons ?? []).joined(separator: ","))
            ])
        }
        return result
    }
}

private func analysisRequestBodyLimit() -> ByteCount {
    let raw = Environment.get("ORCHIVISTE_ANALYSE_BODY_MAX")
        ?? "8mb"
    return ByteCount(stringLiteral: raw)
}

private func applyPolicyReview(
    result: AnalysisResponse,
    threshold: Double
) -> AnalysisResponse {
    guard result.confidence < threshold else {
        return result
    }

    let review = result.review ?? AnalysisReview(
        needs_review: false,
        reasons: [],
        missing_fields: [],
        ambiguous_fields: []
    )
    let reasons = orderedUnique(["low_confidence"] + review.reasons)
    let updatedReview = AnalysisReview(
        needs_review: true,
        reasons: reasons,
        missing_fields: review.missing_fields,
        ambiguous_fields: review.ambiguous_fields
    )
    return AnalysisResponse(
        type_doc: result.type_doc,
        sujets: result.sujets,
        structure: result.structure,
        champs: result.champs,
        confidence: result.confidence,
        suggested_preset: result.suggested_preset,
        suggested_class_code: result.suggested_class_code,
        explanations: result.explanations,
        capture: result.capture,
        review: updatedReview
    )
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
        if seen.insert(value).inserted {
            result.append(value)
        }
    }
    return result
}
