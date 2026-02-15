import Vapor

struct RoutingMap: Content, Codable {
    let mappings: [String: RoutingTarget]
}

struct RoutingTarget: Content, Codable {
    let site: String
    let library: String
    let folder_expr: String
    let metadata: [String: String]?
}

struct RoutingResponse: Content {
    let file_id: String
    let class_code: String
    let target: RoutingTarget
    let resolved_folder: String
    let mode: String
    let destination_url: String?
    let moved_item_id: String?
}
