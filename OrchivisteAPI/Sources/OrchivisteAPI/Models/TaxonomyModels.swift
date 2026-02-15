import Vapor

struct TaxonomyNode: Content, Codable {
    let code: String
    let label: String
    let notes: String?
    let keywords: [String]?
    let synonyms: [String]?
    let children: [TaxonomyNode]?
}

struct TaxonomyRecord: Content, Codable {
    let taxonomy_id: String
    let root: [TaxonomyNode]
}
