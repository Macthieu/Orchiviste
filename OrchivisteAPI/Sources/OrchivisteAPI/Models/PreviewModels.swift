import Vapor

struct PreviewRecord {
    let jobId: UUID
    var pages: Int
    var textPages: [Int: String]
    var imagesByPage: [Int: Data]
    var createdAt: Date
}

struct PreviewTextResponse: Content {
    let page: Int
    let text: String
}
