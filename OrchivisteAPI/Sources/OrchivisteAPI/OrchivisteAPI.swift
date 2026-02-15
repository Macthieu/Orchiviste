import Vapor
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver

@main
struct Boot {
    static func main() throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = Application(env)
        defer { app.shutdown() }

        app.logger.logLevel = .info
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = 8080

        // CORS
        let corsCfg = CORSMiddleware.Configuration(
            allowedOrigin: .originBased,
            allowedMethods: [.GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS],
            allowedHeaders: [.accept, .contentType, .origin, .authorization]
        )
        app.middleware.use(CORSMiddleware(configuration: corsCfg))
        app.middleware.use(RouteLoggingMiddleware(logLevel: .info))

        // DB provider (optionnel)
        let provider = Environment.get("ORCHIVISTE_DB_PROVIDER")?.lowercased()
        if provider == "postgres", let url = Environment.get("ORCHIVISTE_POSTGRES_URL") {
            app.logger.info("Connecting to Postgres at \(url)")
            try app.databases.use(.postgres(url: url), as: .psql)
        } else if provider == "sqlite" || Environment.get("ORCHIVISTE_SQLITE_PATH") != nil {
            let path = Environment.get("ORCHIVISTE_SQLITE_PATH") ?? "orchiviste.sqlite"
            app.logger.info("Connecting to SQLite at \(path)")
            app.databases.use(.sqlite(.file(path)), as: .sqlite)
        }

        // 👉 Enregistre nos routes séparées
        registerHealthRoutes(app)
        registerIngestRoutes(app)
        registerJobRoutes(app)
        registerPreviewRoutes(app)
        registerAnalyseRoutes(app)
        registerPresetRoutes(app)
        registerTaxonomyRoutes(app)
        registerAgendaRoutes(app)
        registerRoutingRoutes(app)
        registerWorkerRoutes(app)
        registerEventRoutes(app)
        registerOpenAPIRoutes(app)

        app.logger.info("➡️ OrchivisteAPI listening on http://127.0.0.1:8080")
        try app.run()
    }
}
