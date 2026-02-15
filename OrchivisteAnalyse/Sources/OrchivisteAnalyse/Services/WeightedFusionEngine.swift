import Vapor

struct WeightedFusionEngine: Sendable {
    let providers: [any AnalysisProvider]

    init(providers: [any AnalysisProvider]) {
        self.providers = providers
    }

    func analyze(request: AnalysisRequest, logger: Logger) async -> AnalysisResponse {
        var candidates: [ProviderCandidate] = []

        for provider in providers {
            do {
                if let output = try await provider.analyze(request: request, logger: logger) {
                    candidates.append(output)
                }
            } catch {
                logger.warning("Analysis provider failed.", metadata: [
                    "provider": .string(provider.name),
                    "error": .string(error.localizedDescription)
                ])
            }
        }

        guard !candidates.isEmpty else {
            return AnalysisResponse(
                type_doc: "Autre",
                sujets: ["General"],
                structure: AnalysisStructure(has_signature: false, pages: 1),
                champs: [:],
                confidence: 0.2,
                suggested_preset: request.preset_id ?? "preset_default",
                suggested_class_code: "GEN-000",
                explanations: AnalysisExplanations(
                    matched_rules: ["fusion_no_provider_output"],
                    top_nodes: ["GEN-000"]
                )
            )
        }

        let selected = candidates.max { lhs, rhs in
            weightedScore(candidate: lhs) < weightedScore(candidate: rhs)
        } ?? candidates[0]

        let allRules = candidates.flatMap(\.matchedRules)
        let allNodes = candidates.flatMap(\.topNodes)

        return AnalysisResponse(
            type_doc: selected.typeDoc,
            sujets: selected.sujets,
            structure: AnalysisStructure(
                has_signature: selected.hasSignature,
                pages: selected.pages
            ),
            champs: selected.champs,
            confidence: selected.confidence,
            suggested_preset: selected.suggestedPreset,
            suggested_class_code: selected.suggestedClassCode,
            explanations: AnalysisExplanations(
                matched_rules: allRules + ["fusion_selected_\(selected.provider)"],
                top_nodes: allNodes.isEmpty ? (selected.suggestedClassCode.map { [$0] } ?? ["GEN-000"]) : allNodes
            )
        )
    }

    private func weightedScore(candidate: ProviderCandidate) -> Double {
        guard let provider = providers.first(where: { $0.name == candidate.provider }) else {
            return candidate.confidence
        }
        return candidate.confidence * provider.weight
    }
}
