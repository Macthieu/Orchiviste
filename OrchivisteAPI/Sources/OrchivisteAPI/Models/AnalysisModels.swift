import Vapor

struct AnalysisRequest: Content {
    let file_id: String
    let text: String?
    let source: JobSource?
    let lang: String?
    let hints: AnalysisHints?
    let preset_id: String?
    let policy: AnalysisPolicy?
}

struct AnalysisHints: Content {
    let session_id: String?
    let agenda_id: String?
}

struct AnalysisPolicy: Content {
    let max_latency_ms: Int?
    let min_confidence: Double?
}

struct AnalysisResponse: Content {
    let type_doc: String
    let sujets: [String]
    let structure: AnalysisStructure
    let champs: [String: String]
    let confidence: Double
    let suggested_preset: String?
    let suggested_class_code: String?
    let explanations: AnalysisExplanations
    let capture: AnalysisCapture?
    let review: AnalysisReview?
}

struct AnalysisStructure: Content {
    let has_signature: Bool
    let pages: Int
}

struct AnalysisExplanations: Content {
    let matched_rules: [String]
    let top_nodes: [String]
}

struct AnalysisCapture: Content {
    let strategy: String
    let unit_count: Int
    let section_titles: [String]
    let boundary_markers: [String]
    let field_sources: [String: AnalysisFieldSource]
    let warnings: [String]
}

struct AnalysisFieldSource: Content {
    let source: String
    let confidence: Double
    let evidence: String?
}

struct AnalysisReview: Content {
    let needs_review: Bool
    let reasons: [String]
    let missing_fields: [String]
    let ambiguous_fields: [String]
}
