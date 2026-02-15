import Vapor

struct CoreMLProvider: AnalysisProvider {
    let name = "CoreML"
    let weight: Double = 0.9

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        logger.debug("CoreML provider disabled in MVP.")
        return nil
    }
}

struct CoginovAPIProvider: AnalysisProvider {
    let name = "CoginovAPI"
    let weight: Double = 0.8

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        logger.debug("Coginov provider disabled in MVP.")
        return nil
    }
}

struct LLMFallbackProvider: AnalysisProvider {
    let name = "LLMFallback"
    let weight: Double = 0.6

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        logger.debug("LLM fallback provider disabled in MVP.")
        return nil
    }
}
