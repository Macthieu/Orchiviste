import Foundation
import Vapor

enum AnalysisProxyClient {
    static func analyzeWithFallback(
        request body: AnalysisRequest,
        correlationId: String?,
        using client: Client,
        logger: Logger
    ) async -> AnalysisResponse {
        do {
            return try await analyzeViaService(
                request: body,
                correlationId: correlationId,
                using: client
            )
        } catch {
            logger.warning("Analyse service unavailable, using local fallback.", metadata: [
                "error": .string(error.localizedDescription),
                "file_id": .string(body.file_id)
            ])
            return localFallback(for: body)
        }
    }

    static func analyzeViaService(
        request body: AnalysisRequest,
        correlationId: String?,
        using client: Client
    ) async throws -> AnalysisResponse {
        let endpoint = analysisEndpoint()
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "application/json")
        headers.replaceOrAdd(name: .accept, value: "application/json")
        if let correlationId, !correlationId.isEmpty {
            headers.replaceOrAdd(name: "x-correlation-id", value: correlationId)
        }

        let response = try await client.post(endpoint, headers: headers) { outgoing in
            try outgoing.content.encode(body)
        }
        guard response.status == .ok else {
            throw Abort(
                .badGateway,
                reason: "Analyse service returned status \(response.status.code)."
            )
        }
        return try response.content.decode(AnalysisResponse.self)
    }

    static func localFallback(for body: AnalysisRequest) -> AnalysisResponse {
        let presets = ConfigLoader.loadPresets()
        let preset = presets.first { $0.id == body.preset_id } ?? presets.first
        let routing = ConfigLoader.loadRoutingMap()
        let classCode = preset?.class_code ?? routing?.mappings.keys.first
        return AnalysisStub.make(
            fileId: body.file_id,
            text: body.text,
            preset: preset,
            classCode: classCode
        )
    }

    private static func analysisEndpoint() -> URI {
        let base = Environment.get("ORCHIVISTE_ANALYSE_URL")
            ?? "http://127.0.0.1:\(Environment.get("ORCHIVISTE_ANALYSE_PORT") ?? "18081")"
        let sanitizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URI(string: "\(sanitizedBase)/v1/analyse")
    }
}
