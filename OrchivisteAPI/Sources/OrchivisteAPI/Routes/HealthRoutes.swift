import Vapor

private let appStart = Date()

struct Health: Content {
    let status: String
    let uptime_s: Double
}

func registerHealthRoutes(_ app: Application) {
    app.get("v1", "health") { _ -> Health in
        Health(status: "ok", uptime_s: max(0, Date().timeIntervalSince(appStart)))
    }
}
