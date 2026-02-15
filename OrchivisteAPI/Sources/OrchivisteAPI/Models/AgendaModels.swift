import Vapor

struct AgendaItem: Content, Codable {
    let no: String
    let titre: String
}

struct AgendaRecord: Content, Codable {
    let agenda_id: String
    let session_id: String
    let date: String
    let items: [AgendaItem]
}
