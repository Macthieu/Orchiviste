import Foundation
import OrchivisteKitContracts
import OrchivisteKitInterop
import Vapor

private struct CockpitExecutableResolution: Sendable {
    var executable: String?
    var reason: String
}

actor CockpitHistoryStore {
    static let shared = CockpitHistoryStore()

    func append(_ entry: CockpitHistoryEntry, to historyURL: URL) throws {
        let directory = historyURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(entry)
        data.append(0x0A)

        if FileManager.default.fileExists(atPath: historyURL.path) {
            let handle = try FileHandle(forWritingTo: historyURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: historyURL, options: [.atomic])
        }
    }

    func read(from historyURL: URL, limit: Int) -> [CockpitHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL), !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        let lines = data.split(separator: 0x0A)
        let decoded = lines.compactMap { line in
            try? decoder.decode(CockpitHistoryEntry.self, from: Data(line))
        }

        let bounded = max(1, min(500, limit))
        return Array(decoded.suffix(bounded).reversed())
    }
}

enum CockpitCanonicalLauncher {
    static func loadRuntimeCatalog(logger: Logger? = nil) -> (config: CockpitConfig, tools: [CockpitToolRuntimeDescriptor]) {
        let config = CockpitConfigLoader.load(logger: logger)
        let tools = config.tools.map { tool in
            let resolution = resolveExecutable(for: tool)
            return CockpitToolRuntimeDescriptor(
                descriptor: tool,
                isAvailable: resolution.executable != nil && tool.enabled,
                resolvedExecutable: resolution.executable,
                availabilityReason: tool.enabled ? resolution.reason : "Tool disabled in cockpit config."
            )
        }
        return (config, tools)
    }

    static func launch(
        _ launchRequest: CockpitLaunchRequest,
        logger: Logger
    ) async throws -> CockpitLaunchOutcome {
        let runtime = loadRuntimeCatalog(logger: logger)

        guard let toolRuntime = runtime.tools.first(where: { $0.descriptor.id == launchRequest.toolID }) else {
            throw Abort(.badRequest, reason: "Tool inconnu: \(launchRequest.toolID)")
        }
        guard toolRuntime.descriptor.enabled else {
            throw Abort(.forbidden, reason: "Tool désactivé dans la configuration cockpit.")
        }

        let tool = toolRuntime.descriptor
        let action = normalizedAction(from: launchRequest.action, fallback: tool.defaultAction)
        let startedAt = isoTimestamp(Date())
        let executionID = UUID().uuidString

        let directories = try prepareRuntimeDirectories(config: runtime.config)
        let requestURL = directories.requestsDirectory
            .appendingPathComponent("\(fileSafeTimestamp())-\(executionID)-request.json")
        let resultURL = directories.resultsDirectory
            .appendingPathComponent("\(fileSafeTimestamp())-\(executionID)-result.json")

        var effectiveParameters = tool.defaultParameters
        for (key, value) in launchRequest.parameters {
            effectiveParameters[key] = value
        }

        if tool.supportsDryRun, effectiveParameters["dry_run"] == nil {
            effectiveParameters["dry_run"] = .bool(true)
        }

        if tool.destructiveRequiresConfirmation {
            let dryRun = boolParameter("dry_run", from: effectiveParameters) ?? true
            if !dryRun {
                guard launchRequest.allowDestructive else {
                    throw Abort(
                        .badRequest,
                        reason: "Exécution destructive bloquée: active le garde-fou explicite allow_destructive=true."
                    )
                }
                if let key = tool.confirmationParameter,
                   boolParameter(key, from: effectiveParameters) != true {
                    throw Abort(
                        .badRequest,
                        reason: "Exécution destructive bloquée: \(key)=true est requis."
                    )
                }
            }
        }

        let request = ToolRequest(
            requestID: UUID().uuidString,
            correlationID: nonEmpty(launchRequest.correlationID),
            tool: tool.id,
            action: action,
            workspacePath: nonEmpty(launchRequest.workspacePath) ?? runtime.config.workspacePath,
            inputArtifacts: launchRequest.inputArtifacts,
            parameters: effectiveParameters,
            requestedAt: startedAt
        )

        do {
            try JSONFileCodec.encode(request, to: requestURL)
        } catch {
            throw Abort(.internalServerError, reason: "Impossible d'écrire le fichier request JSON: \(error.localizedDescription)")
        }

        let resolution = resolveExecutable(for: tool)
        guard let executable = resolution.executable else {
            let finishedAt = isoTimestamp(Date())
            let fallback = makeLaunchFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                code: "TOOL_EXECUTABLE_NOT_FOUND",
                message: resolution.reason,
                metadata: ["tool_id": .string(tool.id)]
            )
            try? JSONFileCodec.encode(fallback, to: resultURL)
            let outcome = CockpitLaunchOutcome(
                executionID: executionID,
                request: request,
                result: fallback,
                command: [tool.executable, "run", "--request", requestURL.path, "--result", resultURL.path],
                requestFile: requestURL,
                resultFile: resultURL,
                historyFile: directories.historyFile,
                exitCode: nil
            )
            try await appendHistory(outcome)
            return outcome
        }

        let arguments = ["run", "--request", requestURL.path, "--result", resultURL.path]
        let command = [executable] + arguments

        let workingDirectory = nonEmpty(tool.repositoryPath).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let shell = await runShell(
            executable: executable,
            arguments: arguments,
            currentDirectory: workingDirectory,
            timeoutSeconds: TimeInterval(runtime.config.toolTimeoutSeconds)
        )

        let finishedAt = isoTimestamp(Date())
        var finalResult: ToolResult
        if FileManager.default.fileExists(atPath: resultURL.path) {
            if let parsed = try? JSONFileCodec.decode(ToolResult.self, from: resultURL) {
                finalResult = parsed
            } else {
                finalResult = makeLaunchFailureResult(
                    request: request,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    code: "RESULT_DECODE_FAILED",
                    message: "Le fichier result.json est illisible ou invalide.",
                    metadata: [
                        "exit_code": .number(Double(shell.exitCode)),
                        "stderr": .string(shell.stderr)
                    ]
                )
                try? JSONFileCodec.encode(finalResult, to: resultURL)
            }
        } else {
            finalResult = makeLaunchFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                code: "RESULT_FILE_MISSING",
                message: "Le CLI n'a pas produit de result.json.",
                metadata: [
                    "exit_code": .number(Double(shell.exitCode)),
                    "stderr": .string(shell.stderr)
                ]
            )
            try? JSONFileCodec.encode(finalResult, to: resultURL)
        }

        if shell.exitCode != 0, finalResult.status == .succeeded {
            var adjustedErrors = finalResult.errors
            adjustedErrors.append(
                ToolError(
                    code: "CLI_EXIT_NONZERO",
                    message: "Le CLI a retourné un code de sortie non nul: \(shell.exitCode)",
                    details: ["stderr": .string(shell.stderr)],
                    retryable: false
                )
            )
            finalResult = ToolResult(
                requestID: finalResult.requestID,
                tool: finalResult.tool,
                status: .failed,
                startedAt: finalResult.startedAt,
                finishedAt: finalResult.finishedAt ?? finishedAt,
                progressEvents: finalResult.progressEvents,
                outputArtifacts: finalResult.outputArtifacts,
                errors: adjustedErrors,
                summary: finalResult.summary ?? "Le CLI a échoué avec un code de sortie non nul.",
                metadata: finalResult.metadata
            )
            try? JSONFileCodec.encode(finalResult, to: resultURL)
        }

        let outcome = CockpitLaunchOutcome(
            executionID: executionID,
            request: request,
            result: finalResult,
            command: command,
            requestFile: requestURL,
            resultFile: resultURL,
            historyFile: directories.historyFile,
            exitCode: shell.exitCode
        )

        try await appendHistory(outcome)
        return outcome
    }

    static func history(limit: Int, logger: Logger? = nil) async -> CockpitHistoryResponse {
        let config = CockpitConfigLoader.load(logger: logger)
        let historyURL = URL(fileURLWithPath: config.historyFile)
        let entries = await CockpitHistoryStore.shared.read(from: historyURL, limit: limit)
        return CockpitHistoryResponse(historyFile: historyURL.path, entries: entries)
    }

    private static func appendHistory(_ outcome: CockpitLaunchOutcome) async throws {
        let entry = CockpitHistoryEntry(
            executionID: outcome.executionID,
            requestID: outcome.request.requestID,
            toolID: outcome.request.tool,
            action: outcome.request.action,
            status: outcome.result.status,
            summary: outcome.result.summary,
            command: outcome.command,
            requestFile: outcome.requestFile.path,
            resultFile: outcome.resultFile.path,
            exitCode: outcome.exitCode,
            startedAt: outcome.result.startedAt ?? isoTimestamp(Date()),
            finishedAt: outcome.result.finishedAt ?? isoTimestamp(Date()),
            dryRun: boolParameter("dry_run", from: outcome.request.parameters),
            errorCodes: outcome.result.errors.map(\.code)
        )
        try await CockpitHistoryStore.shared.append(entry, to: outcome.historyFile)
    }

    private static func resolveExecutable(for tool: CockpitToolDescriptor) -> CockpitExecutableResolution {
        if let explicitPath = nonEmpty(tool.executablePath), isExecutable(explicitPath) {
            return CockpitExecutableResolution(executable: explicitPath, reason: "Executable configured via executable_path.")
        }

        if let repositoryPath = nonEmpty(tool.repositoryPath) {
            let candidate = URL(fileURLWithPath: repositoryPath, isDirectory: true)
                .appendingPathComponent(".build/debug/\(tool.executable)")
                .path
            if isExecutable(candidate) {
                return CockpitExecutableResolution(executable: candidate, reason: "Executable found in \(repositoryPath)/.build/debug.")
            }
        }

        if tool.executable.contains("/") {
            if isExecutable(tool.executable) {
                return CockpitExecutableResolution(executable: tool.executable, reason: "Executable path provided in config.")
            }
            return CockpitExecutableResolution(executable: nil, reason: "Executable path not found: \(tool.executable)")
        }

        if let fromPATH = resolveInPATH(tool.executable) {
            return CockpitExecutableResolution(executable: fromPATH, reason: "Executable resolved from PATH.")
        }

        return CockpitExecutableResolution(
            executable: nil,
            reason: "Executable introuvable. Build attendu dans le dépôt tool ou présence dans PATH."
        )
    }

    private static func prepareRuntimeDirectories(config: CockpitConfig) throws -> (requestsDirectory: URL, resultsDirectory: URL, historyFile: URL) {
        let requestsDirectory = URL(fileURLWithPath: config.requestsDirectory, isDirectory: true)
        let resultsDirectory = URL(fileURLWithPath: config.resultsDirectory, isDirectory: true)
        let historyFile = URL(fileURLWithPath: config.historyFile)

        try FileManager.default.createDirectory(at: requestsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        return (requestsDirectory, resultsDirectory, historyFile)
    }

    private static func runShell(
        executable: String,
        arguments: [String],
        currentDirectory: URL?,
        timeoutSeconds: TimeInterval
    ) async -> ShellCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = ShellCommand.run(
                    executable: executable,
                    arguments: arguments,
                    currentDirectory: currentDirectory,
                    timeoutSeconds: timeoutSeconds,
                    captureOutput: true
                )
                continuation.resume(returning: result)
            }
        }
    }

    private static func resolveInPATH(_ executable: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let components = path
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        for component in components {
            let candidate = URL(fileURLWithPath: component, isDirectory: true)
                .appendingPathComponent(executable)
                .path
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func makeLaunchFailureResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        code: String,
        message: String,
        metadata: [String: JSONValue]
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "launcher",
                    percent: 10,
                    message: "Preparing canonical execution.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .failed,
                    stage: "launcher_failed",
                    percent: 100,
                    message: message,
                    occurredAt: finishedAt,
                    metadata: metadata
                )
            ],
            outputArtifacts: [],
            errors: [
                ToolError(
                    code: code,
                    message: message,
                    details: metadata,
                    retryable: false
                )
            ],
            summary: message,
            metadata: metadata
        )
    }

    private static func boolParameter(_ key: String, from parameters: [String: JSONValue]) -> Bool? {
        guard let value = parameters[key] else { return nil }
        if case .bool(let flag) = value {
            return flag
        }
        return nil
    }

    private static func fileSafeTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func normalizedAction(from rawAction: String?, fallback: String) -> String {
        let fallbackValue = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = rawAction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? fallbackValue : candidate
    }

    private static func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}
