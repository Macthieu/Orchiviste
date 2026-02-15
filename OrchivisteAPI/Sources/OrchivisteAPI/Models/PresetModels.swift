import Vapor

struct Preset: Content, Codable {
    let id: String
    let name: String
    let name_format: String
    let class_code: String?
    let postprocess: [String]?
}
