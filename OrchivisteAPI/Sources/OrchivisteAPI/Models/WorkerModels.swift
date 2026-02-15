import Vapor

enum WorkerStatus: String, Content, Codable {
    case pending
    case approved
}

struct WorkerEnrollRequest: Content {
    let name: String
    let capabilities: [String]?
}

struct WorkerRecord: Content, Codable {
    let id: UUID
    var name: String
    var status: WorkerStatus
    var capabilities: [String]
    var lastSeen: Date?
    var version: String?
    var load: Double?
    var ram_mb: Int?
    var token: String?
}

struct WorkerHeartbeatRequest: Content {
    let version: String?
    let load: Double?
    let ram_mb: Int?
    let capabilities: [String]?
}
