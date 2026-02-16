import Foundation
import Vapor
import Leaf
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver

func configure(_ app: Application) throws {
    app.logger.logLevel = .info
    app.http.server.configuration.hostname = Environment.get("ORCHIVISTE_API_HOST") ?? "127.0.0.1"
    app.http.server.configuration.port = Environment.get("ORCHIVISTE_API_PORT")
        .flatMap(Int.init) ?? 28780

    app.middleware.use(CorrelationIDMiddleware())
    app.middleware.use(CORSMiddleware(configuration: makeCORSConfiguration()))
    app.middleware.use(RouteLoggingMiddleware(logLevel: .info))
    app.views.use(.leaf)
    app.leaf.configuration.rootDirectory = resolveViewsDirectory()

    try configureDatabase(app)
    registerMigrations(app)
    if Environment.get("ORCHIVISTE_AUTO_MIGRATE") == "1" {
        try app.autoMigrate().wait()
    }

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
    registerUIRoutes(app)
}

@main
struct Boot {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do {
            try configure(app)
            app.logger.info("OrchivisteAPI en écoute sur \(app.http.server.configuration.hostname):\(app.http.server.configuration.port)")
            try await app.execute()
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }
}

private func makeCORSConfiguration() -> CORSMiddleware.Configuration {
    let allowedMethods: [HTTPMethod] = [.GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS]
    let allowedHeaders: [HTTPHeaders.Name] = [
        .accept,
        .contentType,
        .origin,
        .authorization,
        .init("x-correlation-id"),
        .init("idempotency-key")
    ]

    let rawOrigins = Environment.get("ORCHIVISTE_CORS_ALLOWED_ORIGINS")
        .map {
            $0.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } ?? []
    if rawOrigins.isEmpty || rawOrigins == ["*"] {
        return .init(
            allowedOrigin: .all,
            allowedMethods: allowedMethods,
            allowedHeaders: allowedHeaders
        )
    }
    return .init(
        allowedOrigin: .originBased,
        allowedMethods: allowedMethods,
        allowedHeaders: allowedHeaders
    )
}

private func configureDatabase(_ app: Application) throws {
    let provider = Environment.get("ORCHIVISTE_DB_PROVIDER")?.lowercased()
    if provider == "postgres", let url = Environment.get("ORCHIVISTE_POSTGRES_URL") {
        app.logger.info("Connexion a Postgres.")
        try app.databases.use(.postgres(url: url), as: .psql)
        app.databases.default(to: .psql)
        return
    }

    let path = Environment.get("ORCHIVISTE_SQLITE_PATH") ?? "orchiviste.sqlite"
    app.logger.info("Connexion a SQLite : \(path)")
    app.databases.use(.sqlite(.file(path)), as: .sqlite)
    app.databases.default(to: .sqlite)
}

private func registerMigrations(_ app: Application) {
    app.migrations.add(CreateJobsMigration())
    app.migrations.add(CreateEventsMigration())
    app.migrations.add(CreateIdempotencyKeysMigration())
}

private func resolveViewsDirectory() -> String {
    if let env = Environment.get("ORCHIVISTE_VIEWS_DIR"), !env.isEmpty {
        return env
    }
    let sourceURL = URL(fileURLWithPath: #filePath)
    let packageRoot = sourceURL
        .deletingLastPathComponent() // OrchivisteAPI.swift
        .deletingLastPathComponent() // OrchivisteAPI
        .deletingLastPathComponent() // Sources
    return packageRoot.appendingPathComponent("Resources/Views", isDirectory: true).path
}
