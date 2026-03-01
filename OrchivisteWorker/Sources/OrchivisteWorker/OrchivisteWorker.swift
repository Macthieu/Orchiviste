import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(PDFKit) && canImport(AppKit)
import PDFKit
import AppKit
#endif
#if canImport(Vision)
import Vision
#endif
import NIOCore
import NIOPosix
import RediStack
import OrchivisteSharedKit

private struct WorkerConfiguration {
    let apiBaseURL: URL
    let workerName: String
    let capabilities: [String]
    let statePath: String
    let workerVersion: String
    let heartbeatSeconds: Int
    let approvalPollSeconds: Int
    let autoApprove: Bool
    let waitForApproval: Bool
    let enableQueue: Bool
    let queueKey: String
    let redisURL: URL?
    let simulatedProcessingSeconds: Double
    let ocrMode: String
    let ocrArtifactDirectory: String?

    static func fromEnvironment(_ env: [String: String]) -> WorkerConfiguration {
        let apiBase = env["ORCHIVISTE_API_BASE"] ?? "http://127.0.0.1:28780"
        let apiBaseURL = URL(string: apiBase) ?? URL(string: "http://127.0.0.1:28780")!
        let workerName = nonEmpty(env["ORCHIVISTE_WORKER_NAME"])
            ?? "worker-\(String(UUID().uuidString.prefix(8)))"

        let capabilities = parseCapabilities(env["ORCHIVISTE_WORKER_CAPABILITIES"]) ?? ["ocr", "preview"]

        let defaultStatePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".orchiviste", isDirectory: true)
            .appendingPathComponent("worker-state.json")
            .path

        let statePath = nonEmpty(env["ORCHIVISTE_WORKER_STATE_PATH"])
            ?? defaultStatePath

        let workerVersion = env["ORCHIVISTE_WORKER_VERSION"] ?? "dev"
        let heartbeatSeconds = max(3, Int(env["ORCHIVISTE_WORKER_HEARTBEAT_SECONDS"] ?? "15") ?? 15)
        let approvalPollSeconds = max(2, Int(env["ORCHIVISTE_WORKER_APPROVAL_POLL_SECONDS"] ?? "5") ?? 5)
        let autoApprove = env["ORCHIVISTE_WORKER_AUTO_APPROVE"] == "1"
        let waitForApproval = env["ORCHIVISTE_WORKER_WAIT_FOR_APPROVAL"] != "0"
        let enableQueue = env["ORCHIVISTE_WORKER_ENABLE_QUEUE"] == "1"
        let queueKey = env["ORCHIVISTE_WORKER_QUEUE_KEY"] ?? "orchiviste:ingest"
        let redisURL = env["ORCHIVISTE_REDIS_URL"].flatMap(URL.init(string:))
        let simulatedProcessingSeconds = Double(env["ORCHIVISTE_WORKER_SIMULATED_PROCESSING_SECONDS"] ?? "1.0") ?? 1.0
        let rawOCRMode = (env["ORCHIVISTE_WORKER_OCR_MODE"] ?? "auto")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowedOCRModes: Set<String> = ["off", "auto", "pdf", "vision"]
        let ocrMode = allowedOCRModes.contains(rawOCRMode) ? rawOCRMode : "auto"
        let ocrArtifactDirectory = nonEmpty(env["ORCHIVISTE_WORKER_OCR_ARTIFACT_DIR"])

        return WorkerConfiguration(
            apiBaseURL: apiBaseURL,
            workerName: workerName,
            capabilities: capabilities,
            statePath: statePath,
            workerVersion: workerVersion,
            heartbeatSeconds: heartbeatSeconds,
            approvalPollSeconds: approvalPollSeconds,
            autoApprove: autoApprove,
            waitForApproval: waitForApproval,
            enableQueue: enableQueue,
            queueKey: queueKey,
            redisURL: redisURL,
            simulatedProcessingSeconds: simulatedProcessingSeconds,
            ocrMode: ocrMode,
            ocrArtifactDirectory: ocrArtifactDirectory
        )
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func parseCapabilities(_ raw: String?) -> [String]? {
        guard let raw else { return nil }
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }
}

private struct PersistedWorkerState: Codable {
    var workerID: UUID
    var workerName: String
    var capabilities: [String]
    var token: String?

    enum CodingKeys: String, CodingKey {
        case workerID = "worker_id"
        case workerName = "worker_name"
        case capabilities
        case token
    }
}

private struct APIWorkerRecord: Codable {
    let id: UUID
    let name: String
    let status: String
    let capabilities: [String]
    let token: String?
    let lastSeen: Date?
    let version: String?
    let load: Double?
    let ramMB: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case capabilities
        case token
        case lastSeen
        case version
        case load
        case ramMB = "ram_mb"
    }
}

private struct WorkerEnrollRequestBody: Encodable {
    let name: String
    let capabilities: [String]
}

private struct WorkerHeartbeatRequestBody: Encodable {
    let version: String?
    let load: Double?
    let ram_mb: Int?
    let capabilities: [String]?
}

private struct WorkerAPIError: Error {
    let statusCode: Int
    let message: String
}

private final class WorkerAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func enroll(name: String, capabilities: [String]) async throws -> APIWorkerRecord {
        let body = WorkerEnrollRequestBody(name: name, capabilities: capabilities)
        return try await sendJSON(
            method: "POST",
            path: "/v1/workers/enroll",
            bearerToken: nil,
            body: body
        )
    }

    func approve(id: UUID) async throws -> APIWorkerRecord {
        return try await sendJSON(
            method: "POST",
            path: "/v1/workers/\(id.uuidString)/approve",
            bearerToken: nil,
            body: Optional<String>.none
        )
    }

    func heartbeat(id: UUID, token: String, version: String, capabilities: [String]) async throws -> APIWorkerRecord {
        let body = WorkerHeartbeatRequestBody(
            version: version,
            load: nil,
            ram_mb: nil,
            capabilities: capabilities
        )
        return try await sendJSON(
            method: "POST",
            path: "/v1/workers/\(id.uuidString)/heartbeat",
            bearerToken: token,
            body: body
        )
    }

    func listWorkers() async throws -> [APIWorkerRecord] {
        return try await sendJSON(
            method: "GET",
            path: "/v1/workers",
            bearerToken: nil,
            body: Optional<String>.none
        )
    }

    private func sendJSON<Response: Decodable, Body: Encodable>(
        method: String,
        path: String,
        bearerToken: String?,
        body: Body?
    ) async throws -> Response {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw WorkerAPIError(statusCode: -1, message: "invalid_http_response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "http_\(http.statusCode)"
            throw WorkerAPIError(statusCode: http.statusCode, message: message)
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: WorkerAPIError(statusCode: -1, message: "empty_http_response"))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private func makeURL(path: String) -> URL {
        if path.hasPrefix("/") {
            return baseURL.appendingPathComponent(String(path.dropFirst()))
        }
        return baseURL.appendingPathComponent(path)
    }
}

private enum WorkerStateStore {
    static func load(path: String) -> PersistedWorkerState? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(PersistedWorkerState.self, from: data)
        } catch {
            print("WARN: unable to load worker state at \(path): \(error)")
            return nil
        }
    }

    static func save(_ state: PersistedWorkerState, path: String) {
        do {
            let fileURL = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("WARN: unable to persist worker state at \(path): \(error)")
        }
    }
}

private struct OCRPageArtifact: Codable {
    let page: Int
    let source: String
    let text: String
}

private struct OCRExtractionArtifact: Codable {
    let job_id: String
    let file_url: String
    let mode: String
    let extracted_at: Date
    let pages: [OCRPageArtifact]
}

private enum WorkerOCR {
    static func extract(fileURLString: String, mode: String) -> [OCRPageArtifact]? {
        guard mode != "off" else {
            return nil
        }
        guard let fileURL = resolveInputFileURL(raw: fileURLString),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        guard fileURL.pathExtension.lowercased() == "pdf" else {
            return nil
        }

        #if canImport(PDFKit) && canImport(AppKit)
        guard let document = PDFDocument(url: fileURL) else {
            return nil
        }
        let pages = max(1, document.pageCount)
        var results: [OCRPageArtifact] = []
        for index in 0..<pages {
            let pageNumber = index + 1
            guard let page = document.page(at: index) else {
                results.append(OCRPageArtifact(page: pageNumber, source: "none", text: ""))
                continue
            }

            var extracted = ""
            var source = "none"

            if mode == "auto" || mode == "pdf" {
                if let text = page.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    extracted = text
                    source = "pdf_text"
                }
            }

            if extracted.isEmpty && (mode == "auto" || mode == "vision") {
                if let ocr = recognizeTextWithVision(page: page),
                   !ocr.isEmpty {
                    extracted = ocr
                    source = "vision_ocr"
                }
            }

            results.append(
                OCRPageArtifact(
                    page: pageNumber,
                    source: source,
                    text: extracted
                )
            )
        }
        return results
        #else
        return nil
        #endif
    }

    static func persist(
        artifact: OCRExtractionArtifact,
        directory: String
    ) {
        do {
            let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(
                at: dirURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let outURL = dirURL.appendingPathComponent("\(artifact.job_id).ocr.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(artifact)
            try data.write(to: outURL, options: .atomic)
        } catch {
            print("WARN: unable to persist OCR artifact: \(error)")
        }
    }

    private static func resolveInputFileURL(raw: String) -> URL? {
        if let parsed = URL(string: raw), parsed.isFileURL {
            return parsed
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(raw)
    }

    #if canImport(PDFKit) && canImport(AppKit) && canImport(Vision)
    private static func recognizeTextWithVision(page: PDFPage) -> String? {
        let pageBounds = page.bounds(for: .mediaBox)
        let safeWidth = max(1, pageBounds.width)
        let ratio = max(0.2, pageBounds.height / safeWidth)
        let size = NSSize(width: 1600, height: max(600, 1600 * ratio))
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let observations = request.results else {
                return nil
            }
            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
    #else
    private static func recognizeTextWithVision(page: Any) -> String? {
        nil
    }
    #endif
}

private final class OptionalQueueConsumer {
    private let key: RedisKey
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let pool: RedisConnectionPool

    init?(redisURL: URL, queueKey: String) {
        guard let host = redisURL.host else {
            return nil
        }
        let port = redisURL.port ?? 6379

        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.key = RedisKey(queueKey)

        do {
            let address = try SocketAddress.makeAddressResolvingHost(host, port: port)
            self.pool = RedisConnectionPool(
                configuration: .init(
                    initialServerConnectionAddresses: [address],
                    maximumConnectionCount: .maximumActiveConnections(2),
                    connectionFactoryConfiguration: .init()
                ),
                boundEventLoop: eventLoopGroup.next()
            )
            self.pool.activate()
        } catch {
            try? eventLoopGroup.syncShutdownGracefully()
            print("WARN: queue consumer disabled, redis init error: \(error)")
            return nil
        }
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    func popNext(timeoutSeconds: Int) throws -> IngestJob? {
        let popped = try pool.leaseConnection { [key = self.key] connection in
            connection.blpop(from: key, timeout: .seconds(Int64(max(0, timeoutSeconds))))
        }.wait()

        guard let payload = popped.string else {
            return nil
        }
        return try JSONDecoder().decode(IngestJob.self, from: Data(payload.utf8))
    }
}

@main
struct Worker {
    static func main() async {
        let config = WorkerConfiguration.fromEnvironment(ProcessInfo.processInfo.environment)
        let apiClient = WorkerAPIClient(baseURL: config.apiBaseURL)

        print("INFO: worker start name=\(config.workerName) api=\(config.apiBaseURL.absoluteString)")

        var state = WorkerStateStore.load(path: config.statePath)
        if state == nil {
            state = await enrollUntilSuccess(apiClient: apiClient, config: config)
        }

        guard var currentState = state else {
            print("ERROR: unable to initialize worker state")
            return
        }

        currentState = await ensureApproval(apiClient: apiClient, config: config, state: currentState)
        WorkerStateStore.save(currentState, path: config.statePath)

        let queueConsumer: OptionalQueueConsumer?
        if config.enableQueue, let redisURL = config.redisURL {
            queueConsumer = OptionalQueueConsumer(redisURL: redisURL, queueKey: config.queueKey)
            if queueConsumer != nil {
                print("INFO: queue consumer enabled key=\(config.queueKey)")
            } else {
                print("WARN: queue consumer requested but not initialized")
            }
        } else {
            queueConsumer = nil
            print("INFO: queue consumer disabled (set ORCHIVISTE_WORKER_ENABLE_QUEUE=1 to enable)")
        }

        var nextHeartbeatAt = Date.distantPast

        while true {
            if Date() >= nextHeartbeatAt {
                if let token = currentState.token, !token.isEmpty {
                    do {
                        let updated = try await apiClient.heartbeat(
                            id: currentState.workerID,
                            token: token,
                            version: config.workerVersion,
                            capabilities: currentState.capabilities
                        )
                        if let refreshedToken = updated.token, refreshedToken != token {
                            currentState.token = refreshedToken
                            WorkerStateStore.save(currentState, path: config.statePath)
                        }
                    } catch let apiError as WorkerAPIError {
                        print("WARN: heartbeat failed status=\(apiError.statusCode) message=\(apiError.message)")
                        if apiError.statusCode == 401 || apiError.statusCode == 404 || apiError.statusCode == 409 {
                            currentState.token = nil
                        }
                    } catch {
                        print("WARN: heartbeat failed \(error)")
                    }
                }
                nextHeartbeatAt = Date().addingTimeInterval(TimeInterval(config.heartbeatSeconds))
            }

            if currentState.token == nil {
                currentState = await ensureApproval(apiClient: apiClient, config: config, state: currentState)
                WorkerStateStore.save(currentState, path: config.statePath)
                nextHeartbeatAt = Date.distantPast
            }

            if let queueConsumer {
                do {
                    if let ingest = try queueConsumer.popNext(timeoutSeconds: 2) {
                        let tags = (ingest.tags ?? []).joined(separator: ",")
                        print(
                            "INFO: simulated process job=\(ingest.taskId.uuidString) source=\(ingest.source) " +
                            "tags=[\(tags)] ocr_mode=\(config.ocrMode)"
                        )

                        let extractedPages = WorkerOCR.extract(
                            fileURLString: ingest.fileURL,
                            mode: config.ocrMode
                        )
                        if let extractedPages {
                            let nonEmptyPages = extractedPages.filter { !$0.text.isEmpty }.count
                            print(
                                "INFO: OCR extraction job=\(ingest.taskId.uuidString) pages=\(extractedPages.count) " +
                                "non_empty=\(nonEmptyPages)"
                            )

                            if let outputDirectory = config.ocrArtifactDirectory {
                                let artifact = OCRExtractionArtifact(
                                    job_id: ingest.taskId.uuidString,
                                    file_url: ingest.fileURL,
                                    mode: config.ocrMode,
                                    extracted_at: Date(),
                                    pages: extractedPages
                                )
                                WorkerOCR.persist(artifact: artifact, directory: outputDirectory)
                            }
                        } else if config.ocrMode != "off" {
                            print("INFO: OCR skipped job=\(ingest.taskId.uuidString) reason=file_unavailable_or_not_supported")
                        }

                        let delay = UInt64(max(0.0, config.simulatedProcessingSeconds) * 1_000_000_000)
                        try? await Task.sleep(nanoseconds: delay)
                    }
                } catch {
                    print("WARN: queue pop failed \(error)")
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            } else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private static func enrollUntilSuccess(
        apiClient: WorkerAPIClient,
        config: WorkerConfiguration
    ) async -> PersistedWorkerState {
        while true {
            do {
                let enrolled = try await apiClient.enroll(name: config.workerName, capabilities: config.capabilities)
                let state = PersistedWorkerState(
                    workerID: enrolled.id,
                    workerName: enrolled.name,
                    capabilities: enrolled.capabilities,
                    token: enrolled.token
                )
                WorkerStateStore.save(state, path: config.statePath)
                print("INFO: worker enrolled id=\(enrolled.id.uuidString) status=\(enrolled.status)")
                return state
            } catch {
                print("WARN: enroll failed, retrying in 3s: \(error)")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private static func ensureApproval(
        apiClient: WorkerAPIClient,
        config: WorkerConfiguration,
        state: PersistedWorkerState
    ) async -> PersistedWorkerState {
        var current = state
        if let token = current.token, !token.isEmpty {
            return current
        }

        if !config.waitForApproval {
            return current
        }

        while current.token == nil {
            do {
                if config.autoApprove {
                    let approved = try await apiClient.approve(id: current.workerID)
                    if let token = approved.token, !token.isEmpty {
                        current.token = token
                        print("INFO: worker auto-approved id=\(approved.id.uuidString)")
                        break
                    }
                }

                let workers = try await apiClient.listWorkers()
                if let refreshed = workers.first(where: { $0.id == current.workerID }) {
                    if let token = refreshed.token, !token.isEmpty {
                        current.token = token
                        print("INFO: worker approved id=\(refreshed.id.uuidString)")
                        break
                    }
                    print("INFO: waiting approval for worker id=\(current.workerID.uuidString) status=\(refreshed.status)")
                } else {
                    print("WARN: worker id not found on API, re-enrolling")
                    current = await enrollUntilSuccess(apiClient: apiClient, config: config)
                    if current.token != nil {
                        break
                    }
                }
            } catch {
                print("WARN: approval polling failed: \(error)")
            }

            try? await Task.sleep(nanoseconds: UInt64(config.approvalPollSeconds) * 1_000_000_000)
        }

        return current
    }
}
