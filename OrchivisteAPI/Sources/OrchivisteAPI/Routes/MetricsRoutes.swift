import Vapor

func registerMetricsRoutes(_ app: Application) {
    app.get("v1", "metrics") { req async throws -> RequestMetricsSnapshot in
        await req.application.requestMetricsRegistry.snapshot()
    }
}
