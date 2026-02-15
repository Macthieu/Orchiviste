import Vapor

protocol AnalysisProvider: Sendable {
    var name: String { get }
    var weight: Double { get }
    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate?
}
