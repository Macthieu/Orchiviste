import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

private struct RemoteAnalysisRequest: Encodable {
    let file_id: String
    let text: String?
    let source: AnalysisSource?
    let lang: String?
    let hints: AnalysisHints?
    let preset_id: String?
    let policy: AnalysisPolicy?
    let model: String?
}

private struct RemoteWrappedAnalysisResponse: Decodable {
    let result: AnalysisResponse?
    let data: AnalysisResponse?
}

private struct RemoteProviderClient {
    let name: String
    let endpoint: URL
    let token: String?
    let timeoutSeconds: TimeInterval
    let model: String?

    func call(request: AnalysisRequest, logger: Logger) async throws -> AnalysisResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: configuration)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue(name, forHTTPHeaderField: "x-orchiviste-provider")

        let body = RemoteAnalysisRequest(
            file_id: request.file_id,
            text: request.text,
            source: request.source,
            lang: request.lang,
            hints: request.hints,
            preset_id: request.preset_id,
            policy: request.policy,
            model: model
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await perform(urlRequest, with: session)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Abort(.badGateway, reason: "Réponse HTTP invalide du fournisseur \(name).")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? ""
            let clipped = payload.count > 220 ? String(payload.prefix(220)) : payload
            throw Abort(
                .badGateway,
                reason: "Le fournisseur \(name) a retourné HTTP \(httpResponse.statusCode). \(clipped)"
            )
        }

        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(AnalysisResponse.self, from: data) {
            return decoded
        }
        if let wrapped = try? decoder.decode(RemoteWrappedAnalysisResponse.self, from: data) {
            if let result = wrapped.result {
                return result
            }
            if let result = wrapped.data {
                return result
            }
        }
        throw Abort(.badGateway, reason: "Format de réponse non supporté pour le fournisseur \(name).")
    }

    private func perform(
        _ request: URLRequest,
        with session: URLSession
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: Abort(.badGateway, reason: "Réponse vide du fournisseur distant."))
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
    }
}

private func providerEnabled(_ key: String) -> Bool {
    let raw = (Environment.get(key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
}

private func providerURL(_ key: String) -> URL? {
    guard let raw = Environment.get(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return nil
    }
    return URL(string: raw)
}

private func providerTimeoutSeconds(
    envKey: String,
    request: AnalysisRequest,
    defaultMs: Int
) -> TimeInterval {
    let providerMs = max(
        150,
        Int(Environment.get(envKey) ?? "\(defaultMs)") ?? defaultMs
    )
    if let requestedMax = request.policy?.max_latency_ms, requestedMax > 0 {
        return Double(min(providerMs, requestedMax)) / 1000.0
    }
    return Double(providerMs) / 1000.0
}

private func buildCandidate(
    providerName: String,
    response: AnalysisResponse
) -> ProviderCandidate {
    let confidence = min(0.99, max(0.0, response.confidence))
    var rules = response.explanations.matched_rules
    rules.append("remote_provider_\(providerName.lowercased())")
    return ProviderCandidate(
        provider: providerName,
        typeDoc: response.type_doc,
        sujets: response.sujets,
        hasSignature: response.structure.has_signature,
        pages: max(1, response.structure.pages),
        champs: response.champs,
        confidence: confidence,
        suggestedPreset: response.suggested_preset,
        suggestedClassCode: response.suggested_class_code,
        matchedRules: rules,
        topNodes: response.explanations.top_nodes
    )
}

struct CoreMLProvider: AnalysisProvider {
    let name = "CoreML"
    let weight: Double = 0.9

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        guard providerEnabled("ORCHIVISTE_ANALYSE_PROVIDER_COREML_ENABLED") else {
            return nil
        }
        guard let endpoint = providerURL("ORCHIVISTE_ANALYSE_PROVIDER_COREML_URL") else {
            logger.warning("CoreML activé mais URL absente.")
            return nil
        }

        let client = RemoteProviderClient(
            name: name,
            endpoint: endpoint,
            token: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_COREML_TOKEN"),
            timeoutSeconds: providerTimeoutSeconds(
                envKey: "ORCHIVISTE_ANALYSE_PROVIDER_COREML_TIMEOUT_MS",
                request: request,
                defaultMs: 1200
            ),
            model: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_COREML_MODEL")
        )
        let response = try await client.call(request: request, logger: logger)
        return buildCandidate(providerName: name, response: response)
    }
}

struct CoginovAPIProvider: AnalysisProvider {
    let name = "CoginovAPI"
    let weight: Double = 0.8

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        guard providerEnabled("ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_ENABLED") else {
            return nil
        }
        guard let endpoint = providerURL("ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_URL") else {
            logger.warning("Coginov activé mais URL absente.")
            return nil
        }

        let client = RemoteProviderClient(
            name: name,
            endpoint: endpoint,
            token: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_TOKEN"),
            timeoutSeconds: providerTimeoutSeconds(
                envKey: "ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_TIMEOUT_MS",
                request: request,
                defaultMs: 1500
            ),
            model: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_MODEL")
        )
        let response = try await client.call(request: request, logger: logger)
        return buildCandidate(providerName: name, response: response)
    }
}

struct LLMFallbackProvider: AnalysisProvider {
    let name = "LLMFallback"
    let weight: Double = 0.6

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        guard providerEnabled("ORCHIVISTE_ANALYSE_PROVIDER_LLM_ENABLED") else {
            return nil
        }
        guard let endpoint = providerURL("ORCHIVISTE_ANALYSE_PROVIDER_LLM_URL") else {
            logger.warning("LLM fallback activé mais URL absente.")
            return nil
        }

        let client = RemoteProviderClient(
            name: name,
            endpoint: endpoint,
            token: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_LLM_TOKEN"),
            timeoutSeconds: providerTimeoutSeconds(
                envKey: "ORCHIVISTE_ANALYSE_PROVIDER_LLM_TIMEOUT_MS",
                request: request,
                defaultMs: 2500
            ),
            model: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_LLM_MODEL")
        )
        let response = try await client.call(request: request, logger: logger)
        return buildCandidate(providerName: name, response: response)
    }
}
