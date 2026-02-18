import Foundation
import Vapor

struct RequestMetricsSnapshot: Content {
    let started_at: Date
    let uptime_s: Double
    let total_requests: Int
    let in_flight: Int
    let by_status: [String: Int]
    let by_method: [String: Int]
    let top_routes: [RouteMetricSnapshot]
    let latency_ms: LatencySnapshot
}

struct RouteMetricSnapshot: Content {
    let route: String
    let count: Int
    let avg_ms: Double
    let max_ms: Double
}

struct LatencySnapshot: Content {
    let avg: Double
    let max: Double
}

private struct RouteAccumulator: Sendable {
    var count: Int = 0
    var totalLatencyMs: Double = 0
    var maxLatencyMs: Double = 0

    mutating func add(_ latencyMs: Double) {
        count += 1
        totalLatencyMs += latencyMs
        maxLatencyMs = max(maxLatencyMs, latencyMs)
    }

    var averageLatencyMs: Double {
        guard count > 0 else { return 0 }
        return totalLatencyMs / Double(count)
    }
}

actor RequestMetricsRegistry {
    private let startedAt = Date()
    private var totalRequests: Int = 0
    private var inFlight: Int = 0
    private var statusCounts: [Int: Int] = [:]
    private var methodCounts: [String: Int] = [:]
    private var routeStats: [String: RouteAccumulator] = [:]
    private var latencyTotalMs: Double = 0
    private var latencyMaxMs: Double = 0

    func begin() {
        totalRequests += 1
        inFlight += 1
    }

    func finish(
        method: String,
        path: String,
        status: Int,
        latencyMs: Double
    ) {
        inFlight = max(0, inFlight - 1)
        statusCounts[status, default: 0] += 1
        methodCounts[method, default: 0] += 1
        routeStats[path, default: RouteAccumulator()].add(latencyMs)

        latencyTotalMs += latencyMs
        latencyMaxMs = max(latencyMaxMs, latencyMs)
    }

    func snapshot() -> RequestMetricsSnapshot {
        let routeMetrics = routeStats
            .map { route, acc in
                RouteMetricSnapshot(
                    route: route,
                    count: acc.count,
                    avg_ms: rounded(acc.averageLatencyMs),
                    max_ms: rounded(acc.maxLatencyMs)
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.route < rhs.route
                }
                return lhs.count > rhs.count
            }

        let avgLatency = totalRequests > 0 ? (latencyTotalMs / Double(totalRequests)) : 0
        let byStatus = Dictionary(uniqueKeysWithValues: statusCounts.map { (String($0.key), $0.value) })

        return RequestMetricsSnapshot(
            started_at: startedAt,
            uptime_s: max(0, Date().timeIntervalSince(startedAt)),
            total_requests: totalRequests,
            in_flight: inFlight,
            by_status: byStatus,
            by_method: methodCounts,
            top_routes: Array(routeMetrics.prefix(25)),
            latency_ms: LatencySnapshot(
                avg: rounded(avgLatency),
                max: rounded(latencyMaxMs)
            )
        )
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

struct RequestMetricsMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let startNs = DispatchTime.now().uptimeNanoseconds
        await req.application.requestMetricsRegistry.begin()

        do {
            let response = try await next.respond(to: req)
            let latencyMs = elapsedMilliseconds(since: startNs)
            await req.application.requestMetricsRegistry.finish(
                method: req.method.rawValue,
                path: normalizedPath(req.url.path),
                status: Int(response.status.code),
                latencyMs: latencyMs
            )
            return response
        } catch {
            let latencyMs = elapsedMilliseconds(since: startNs)
            let status = Int((error as? AbortError)?.status.code ?? 500)
            await req.application.requestMetricsRegistry.finish(
                method: req.method.rawValue,
                path: normalizedPath(req.url.path),
                status: status,
                latencyMs: latencyMs
            )
            throw error
        }
    }

    private func elapsedMilliseconds(since startNs: UInt64) -> Double {
        let endNs = DispatchTime.now().uptimeNanoseconds
        let durationNs = endNs >= startNs ? (endNs - startNs) : 0
        return Double(durationNs) / 1_000_000.0
    }

    private func normalizedPath(_ raw: String) -> String {
        let segments = raw
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { segment -> String in
                let value = String(segment)
                if UUID(uuidString: value) != nil {
                    return "{uuid}"
                }
                if Int(value) != nil {
                    return "{int}"
                }
                if value.hasSuffix(".jpg") {
                    let base = String(value.dropLast(4))
                    if Int(base) != nil {
                        return "{int}.jpg"
                    }
                }
                return value
            }
        if segments.isEmpty {
            return "/"
        }
        return "/" + segments.joined(separator: "/")
    }
}

extension Application {
    private struct RequestMetricsRegistryKey: StorageKey {
        typealias Value = RequestMetricsRegistry
    }

    var requestMetricsRegistry: RequestMetricsRegistry {
        if let existing = storage[RequestMetricsRegistryKey.self] {
            return existing
        }
        let created = RequestMetricsRegistry()
        storage[RequestMetricsRegistryKey.self] = created
        return created
    }
}
