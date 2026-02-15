import Vapor

struct CoreMLProvider: AnalysisProvider {
    let name = "CoreML"
    let weight: Double = 0.9

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        logger.debug("Fournisseur CoreML desactive pour le MVP.")
        return nil
    }
}

struct CoginovAPIProvider: AnalysisProvider {
    let name = "CoginovAPI"
    let weight: Double = 0.8

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        logger.debug("Fournisseur Coginov desactive pour le MVP.")
        return nil
    }
}

struct LLMFallbackProvider: AnalysisProvider {
    let name = "LLMFallback"
    let weight: Double = 0.6

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        logger.debug("Fournisseur LLM de secours desactive pour le MVP.")
        return nil
    }
}
