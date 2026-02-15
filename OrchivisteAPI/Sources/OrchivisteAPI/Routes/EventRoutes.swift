import Vapor

func registerEventRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.get("events") { req async throws -> EventsResponse in
            let cursor = (try? req.query.get(Int.self, at: "cursor")) ?? 0
            return await req.application.appState.events(after: cursor)
        }
    }
}
