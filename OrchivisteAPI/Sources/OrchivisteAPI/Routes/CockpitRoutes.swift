import Vapor

func registerCockpitRoutes(_ app: Application) {
    app.group("v1", "cockpit") { cockpit in
        cockpit.get("tools") { req async throws -> [CockpitToolRuntimeDescriptor] in
            let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
            return runtime.tools
        }

        cockpit.get("config") { req async throws -> CockpitConfigSummary in
            let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
            return CockpitConfigSummary(
                workspacePath: runtime.config.workspacePath,
                runtimeDirectory: runtime.config.runtimeDirectory,
                requestsDirectory: runtime.config.requestsDirectory,
                resultsDirectory: runtime.config.resultsDirectory,
                historyFile: runtime.config.historyFile,
                toolTimeoutSeconds: runtime.config.toolTimeoutSeconds
            )
        }

        cockpit.get("history") { req async throws -> CockpitHistoryResponse in
            let requestedLimit = req.query[Int.self, at: "limit"] ?? 50
            return await CockpitCanonicalLauncher.history(limit: requestedLimit, on: req.db, logger: req.logger)
        }

        cockpit.post("runs") { req async throws -> CockpitRunResponsePayload in
            let payload = try req.content.decode(CockpitRunRequestPayload.self)
            let launchRequest = CockpitLaunchRequest(
                toolID: payload.toolID,
                action: payload.action,
                correlationID: payload.correlationID,
                workspacePath: payload.workspacePath,
                inputArtifacts: payload.inputArtifacts ?? [],
                parameters: payload.parameters ?? [:],
                allowDestructive: payload.allowDestructive ?? false
            )

            let outcome = try await CockpitCanonicalLauncher.launch(launchRequest, on: req.db, logger: req.logger)
            return CockpitRunResponsePayload(
                executionID: outcome.executionID,
                requestID: outcome.request.requestID,
                toolID: outcome.request.tool,
                action: outcome.request.action,
                status: outcome.result.status,
                summary: outcome.result.summary,
                command: outcome.command,
                requestFile: outcome.requestFile.path,
                resultFile: outcome.resultFile.path,
                historyFile: outcome.historyFile.path,
                exitCode: outcome.exitCode,
                startedAt: outcome.result.startedAt ?? "",
                finishedAt: outcome.result.finishedAt ?? "",
                errors: outcome.result.errors
            )
        }
    }
}
