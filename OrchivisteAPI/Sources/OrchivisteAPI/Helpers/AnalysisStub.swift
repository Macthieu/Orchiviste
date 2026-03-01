import Foundation

enum AnalysisStub {
    static func make(fileId: String, text: String?, preset: Preset?, classCode: String?) -> AnalysisResponse {
        let lower = fileId.lowercased()
        let isResolution = lower.contains("resolution") || lower.contains("res")
        let typeDoc = isResolution ? "Resolution" : "ProcesVerbal"
        let confidence: Double = lower.contains("low") ? 0.42 : 0.88
        let sujets = isResolution ? ["Decision", "Budget"] : ["Comite", "Session"]
        let pages = max(1, min(12, (text?.split(separator: "\n").count ?? 1)))

        return AnalysisResponse(
            type_doc: typeDoc,
            sujets: sujets,
            structure: AnalysisStructure(has_signature: lower.contains("signature"), pages: pages),
            champs: [
                "numero": isResolution ? "R-2024-001" : "PV-2024-001",
                "date": "2024-01-15",
                "comite": "Conseil",
                "summary.title": isResolution ? "Résolution budgétaire" : "Procès-verbal de séance",
                "summary.generated": isResolution
                    ? "Résolution municipale suggérée avec numéro, date et comité détectés. Vérifier le contenu exact avant diffusion."
                    : "Procès-verbal suggéré avec date et comité détectés. Vérifier les décisions et participants avant diffusion.",
                "summary.highlights": isResolution
                    ? "Numéro: R-2024-001 | Date: 2024-01-15 | Émetteur: Conseil"
                    : "Numéro: PV-2024-001 | Date: 2024-01-15 | Comité: Conseil",
                "metadata.type_document": typeDoc,
                "metadata.numero_document": isResolution ? "R-2024-001" : "PV-2024-001",
                "metadata.date_document": "2024-01-15",
                "metadata.organisme_emetteur": "Conseil",
                "metadata.objet": isResolution ? "Décision budgétaire municipale" : "Séance du comité"
            ],
            confidence: confidence,
            suggested_preset: preset?.id,
            suggested_class_code: classCode ?? preset?.class_code,
            explanations: AnalysisExplanations(
                matched_rules: ["stub_rule_title", "stub_rule_keywords"],
                top_nodes: [classCode ?? preset?.class_code ?? "UNCLASSIFIED"]
            ),
            capture: AnalysisCapture(
                strategy: "fallback_stub",
                unit_count: 1,
                section_titles: [],
                boundary_markers: [],
                field_sources: [
                    "numero": AnalysisFieldSource(
                        source: "stub_default",
                        confidence: 0.6,
                        evidence: isResolution ? "R-2024-001" : "PV-2024-001"
                    )
                ],
                warnings: ["analysis_service_unavailable"]
            ),
            review: confidence < 0.7 ? AnalysisReview(
                needs_review: true,
                reasons: ["low_confidence", "analysis_service_unavailable"],
                missing_fields: [],
                ambiguous_fields: []
            ) : AnalysisReview(
                needs_review: false,
                reasons: ["analysis_service_unavailable"],
                missing_fields: [],
                ambiguous_fields: []
            )
        )
    }
}
