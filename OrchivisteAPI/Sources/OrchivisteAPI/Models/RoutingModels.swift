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

struct RoutingRequest: Content {
    let class_code: String?
    let preset_id: String?
    let destination_folder: String?
    let name_format: String?
}

struct RoutingLocalSettings: Content, Codable {
    let local_route_root: String?
    let default_destination_template: String?
    let default_name_format: String?
}

struct RoutingRuleSet: Content, Codable {
    let rules: [RoutingRule]
}

struct RoutingRule: Content, Codable {
    let id: String?
    let when_type_doc: String?
    let when_sujet: String?
    let when_class_code: String?
    let class_code: String?
    let preset_id: String?
    let destination_template: String?
    let name_format: String?
}

struct RoutingResponse: Content {
    let file_id: String
    let class_code: String
    let target: RoutingTarget
    let resolved_folder: String
    let mode: String
    let destination_url: String?
    let moved_item_id: String?
    let destination_local_path: String?
    let resolved_file_name: String?
}
