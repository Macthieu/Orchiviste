import Fluent

struct CreateJobsMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(JobRow.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("status", .string, .required)
            .field("file_url", .string, .required)
            .field("source_kind", .string, .required)
            .field("source_url", .string)
            .field("source_site", .string)
            .field("source_library", .string)
            .field("source_item_id", .string)
            .field("tags_json", .string, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("ingest_received_at", .datetime)
            .field("preview_ready_at", .datetime)
            .field("analysed_at", .datetime)
            .field("routed_at", .datetime)
            .field("completed_at", .datetime)
            .field("suggested_preset", .string)
            .field("suggested_class_code", .string)
            .field("confidence", .double)
            .field("needs_review", .bool, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(JobRow.schema).delete()
    }
}

struct CreateEventsMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(EventRow.schema)
            .field("id", .int, .identifier(auto: true))
            .field("type", .string, .required)
            .field("created_at", .datetime, .required)
            .field("payload_json", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EventRow.schema).delete()
    }
}

struct CreateIdempotencyKeysMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(IdempotencyKeyRow.schema)
            .field("id", .int, .identifier(auto: true))
            .field("key", .string, .required)
            .field("request_hash", .string, .required)
            .field("job_id", .uuid, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "key")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(IdempotencyKeyRow.schema).delete()
    }
}

struct CreateWorkersMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(WorkerRow.schema)
            .field("id", .uuid, .identifier(auto: false))
            .field("name", .string, .required)
            .field("status", .string, .required)
            .field("capabilities_json", .string, .required)
            .field("last_seen_at", .datetime)
            .field("version", .string)
            .field("load", .double)
            .field("ram_mb", .int)
            .field("token", .string)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(WorkerRow.schema).delete()
    }
}
