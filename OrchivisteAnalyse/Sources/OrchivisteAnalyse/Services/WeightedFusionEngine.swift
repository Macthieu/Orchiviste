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
                logger.warning("Échec d'un fournisseur d'analyse.", metadata: [
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
                ),
                capture: AnalysisCapture(
                    strategy: "fallback_without_provider",
                    unit_count: 1,
                    section_titles: [],
                    boundary_markers: [],
                    field_sources: [:],
                    warnings: ["no_provider_output"]
                ),
                review: AnalysisReview(
                    needs_review: true,
                    reasons: ["no_provider_output"],
                    missing_fields: [],
                    ambiguous_fields: []
                )
            )
        }

        let selected = candidates.max { lhs, rhs in
            weightedScore(candidate: lhs) < weightedScore(candidate: rhs)
        } ?? candidates[0]

        let allRules = candidates.flatMap(\.matchedRules)
        let allNodes = candidates.flatMap(\.topNodes)
        let mergedReview = mergeReview(candidates: candidates)
        let mergedCapture = mergeCapture(selected: selected, candidates: candidates)

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
            ),
            capture: mergedCapture,
            review: mergedReview
        )
    }

    private func weightedScore(candidate: ProviderCandidate) -> Double {
        guard let provider = providers.first(where: { $0.name == candidate.provider }) else {
            return candidate.confidence
        }
        return candidate.confidence * provider.weight
    }

    private func mergeReview(candidates: [ProviderCandidate]) -> AnalysisReview? {
        let reviews = candidates.compactMap(\.review)
        guard !reviews.isEmpty else {
            return nil
        }
        let reasons = orderedUnique(reviews.flatMap(\.reasons))
        let missingFields = orderedUnique(reviews.flatMap(\.missing_fields))
        let ambiguousFields = orderedUnique(reviews.flatMap(\.ambiguous_fields))
        return AnalysisReview(
            needs_review: reviews.contains(where: \.needs_review),
            reasons: reasons,
            missing_fields: missingFields,
            ambiguous_fields: ambiguousFields
        )
    }

    private func mergeCapture(
        selected: ProviderCandidate,
        candidates: [ProviderCandidate]
    ) -> AnalysisCapture? {
        guard let selectedCapture = selected.capture else {
            return candidates.compactMap(\.capture).first
        }
        let warnings = orderedUnique(candidates.compactMap(\.capture).flatMap(\.warnings))
        let fieldSources = candidates.compactMap(\.capture).reduce(into: selectedCapture.field_sources) { partial, capture in
            for (key, value) in capture.field_sources where partial[key] == nil {
                partial[key] = value
            }
        }
        return AnalysisCapture(
            strategy: selectedCapture.strategy,
            unit_count: selectedCapture.unit_count,
            section_titles: selectedCapture.section_titles,
            boundary_markers: selectedCapture.boundary_markers,
            field_sources: fieldSources,
            warnings: warnings
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
}
