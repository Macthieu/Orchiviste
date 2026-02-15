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
                "comite": "Conseil"
            ],
            confidence: confidence,
            suggested_preset: preset?.id,
            suggested_class_code: classCode ?? preset?.class_code,
            explanations: AnalysisExplanations(
                matched_rules: ["stub_rule_title", "stub_rule_keywords"],
                top_nodes: [classCode ?? preset?.class_code ?? "UNCLASSIFIED"]
            )
        )
    }
}
