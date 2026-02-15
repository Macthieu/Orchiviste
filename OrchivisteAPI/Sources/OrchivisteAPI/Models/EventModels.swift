import Vapor

struct EventRecord: Content, Codable {
    let id: Int
    let type: String
    let created_at: Date
    let payload: [String: String]
}

struct EventsResponse: Content {
    let cursor: Int
    let events: [EventRecord]
}
