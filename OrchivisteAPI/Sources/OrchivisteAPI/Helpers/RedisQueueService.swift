import Foundation
import NIOCore
@preconcurrency import RediStack
import Vapor

struct QueueStatsResponse: Content {
    let ingest_depth: Int
    let dead_letter_depth: Int
}

struct QueueEnqueueResult: Sendable {
    let enqueued: Bool
    let queue: String
}

enum RedisQueueService {
    private static let ingestKey = RedisKey(Environment.get("ORCHIVISTE_REDIS_INGEST_KEY") ?? "orchiviste:ingest")
    private static let deadLetterKey = RedisKey(Environment.get("ORCHIVISTE_REDIS_DEADLETTER_KEY") ?? "orchiviste:ingest:dead-letter")

    static func enqueueIngest(
        payload: Data,
        application: Application,
        logger: Logger
    ) async -> QueueEnqueueResult {
        await enqueue(data: payload, key: ingestKey, application: application, logger: logger)
    }

    static func enqueueDeadLetter(
        payload: Data,
        reason: String,
        application: Application,
        logger: Logger
    ) async {
        var envelope: [String: String] = ["reason": reason]
        envelope["payload_base64"] = payload.base64EncodedString()
        guard let encoded = try? JSONEncoder().encode(envelope) else { return }
        _ = await enqueue(data: encoded, key: deadLetterKey, application: application, logger: logger)
    }

    static func queueStats(application: Application, logger: Logger) async -> QueueStatsResponse {
        guard let connection = try? await makeConnection(application: application).get() else {
            return QueueStatsResponse(ingest_depth: 0, dead_letter_depth: 0)
        }
        defer {
            Task { _ = try? await connection.close().get() }
        }
        do {
            let ingest = try await connection.llen(of: ingestKey).get()
            let dead = try await connection.llen(of: deadLetterKey).get()
            return QueueStatsResponse(
                ingest_depth: Int(truncatingIfNeeded: ingest),
                dead_letter_depth: Int(truncatingIfNeeded: dead)
            )
        } catch {
            logger.warning("Impossible de récupérer les statistiques de file Redis.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return QueueStatsResponse(ingest_depth: 0, dead_letter_depth: 0)
        }
    }

    private static func enqueue(
        data: Data,
        key: RedisKey,
        application: Application,
        logger: Logger
    ) async -> QueueEnqueueResult {
        guard let connection = try? await makeConnection(application: application).get() else {
            return QueueEnqueueResult(enqueued: false, queue: key.description)
        }
        defer {
            Task { _ = try? await connection.close().get() }
        }

        do {
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)
            let value = RESPValue.bulkString(buffer)
            _ = try await connection.rpush([value], into: key).get()
            return QueueEnqueueResult(enqueued: true, queue: key.description)
        } catch {
            logger.warning("Impossible d'empiler la charge dans la file Redis.", metadata: [
                "queue": .string(key.description),
                "error": .string(error.localizedDescription)
            ])
            return QueueEnqueueResult(enqueued: false, queue: key.description)
        }
    }

    private static func makeConnection(application: Application) throws -> EventLoopFuture<RedisConnection> {
        guard let redisURL = Environment.get("ORCHIVISTE_REDIS_URL"),
              let url = URL(string: redisURL),
              let host = url.host else {
            throw Abort(.serviceUnavailable, reason: "ORCHIVISTE_REDIS_URL n'est pas configure.")
        }
        let port = url.port ?? 6379
        let config = try RedisConnection.Configuration(hostname: host, port: port)
        return RedisConnection.make(
            configuration: config,
            boundEventLoop: application.eventLoopGroup.next()
        )
    }
}
