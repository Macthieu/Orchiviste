import Foundation
import OrchivisteKitContracts
import Vapor

private struct UICockpitToolCard: Encodable {
    let id: String
    let display_name: String
    let mission: String
    let version: String
    let integration_status: String
    let capabilities: String
    let is_available: Bool
    let availability_label: String
    let availability_class: String
    let availability_reason: String
    let selected_attribute: String
    let default_action: String
    let default_parameters_json: String
    let repository_path: String
}

private struct UICockpitHistoryRow: Encodable {
    let execution_id: String
    let request_id: String
    let tool_id: String
    let action: String
    let status: String
    let status_label: String
    let summary: String
    let started_at: String
    let finished_at: String
    let exit_code: String
    let request_file: String
    let result_file: String
}

private struct UICockpitContext: Encodable {
    let tools: [UICockpitToolCard]
    let tools_present: Bool
    let selected_tool_id: String
    let selected_action: String
    let selected_workspace_path: String
    let selected_parameters_json: String
    let selected_input_artifacts_json: String
    let selected_allow_destructive_attr: String
    let history_rows: [UICockpitHistoryRow]
    let history_present: Bool
    let history_file: String
    let notice: String?
    let error: String?
}

private struct UICockpitRunForm: Content {
    let tool_id: String
    let action: String?
    let workspace_path: String?
    let parameters_json: String?
    let input_artifacts_json: String?
    let allow_destructive: String?
}

func registerCockpitUIRoutes(_ app: Application) {
    let renderPilotageView: @Sendable (Request) async throws -> View = { req in
        let runtime = CockpitCanonicalLauncher.loadRuntimeCatalog(logger: req.logger)
        let selectedToolID = nonEmpty(req.query[String.self, at: "tool"]) ?? runtime.tools.first?.descriptor.id ?? ""
        let selectedTool = runtime.tools.first(where: { $0.descriptor.id == selectedToolID }) ?? runtime.tools.first

        let selectedAction = nonEmpty(req.query[String.self, at: "action"]) ?? selectedTool?.descriptor.defaultAction ?? "run"
        let selectedWorkspacePath = nonEmpty(req.query[String.self, at: "workspace_path"]) ?? runtime.config.workspacePath
        let selectedParametersJSON = nonEmpty(req.query[String.self, at: "parameters_json"]) ?? prettyJSONString(selectedTool?.descriptor.defaultParameters ?? [:])
        let selectedInputArtifactsJSON = nonEmpty(req.query[String.self, at: "input_artifacts_json"]) ?? "[]"
        let selectedAllowDestructive = parseBooleanFlag(req.query[String.self, at: "allow_destructive"], defaultValue: false)

        let history = await CockpitCanonicalLauncher.history(limit: 25, logger: req.logger)

        let toolCards = runtime.tools.map { tool in
            UICockpitToolCard(
                id: tool.descriptor.id,
                display_name: tool.descriptor.displayName,
                mission: tool.descriptor.mission,
                version: tool.descriptor.version,
                integration_status: tool.descriptor.integrationStatus,
                capabilities: tool.descriptor.capabilities.joined(separator: ", "),
                is_available: tool.isAvailable,
                availability_label: tool.isAvailable ? "Prêt" : "Non prêt",
                availability_class: tool.isAvailable ? "ok" : "ko",
                availability_reason: tool.availabilityReason,
                selected_attribute: tool.descriptor.id == selectedToolID ? "selected" : "",
                default_action: tool.descriptor.defaultAction,
                default_parameters_json: prettyJSONString(tool.descriptor.defaultParameters),
                repository_path: tool.descriptor.repositoryPath ?? "-"
            )
        }

        let historyRows = history.entries.map { entry in
            UICockpitHistoryRow(
                execution_id: entry.executionID,
                request_id: entry.requestID,
                tool_id: entry.toolID,
                action: entry.action,
                status: entry.status.rawValue,
                status_label: uiStatusLabel(entry.status),
                summary: entry.summary ?? "-",
                started_at: entry.startedAt,
                finished_at: entry.finishedAt,
                exit_code: entry.exitCode.map(String.init) ?? "-",
                request_file: entry.requestFile,
                result_file: entry.resultFile
            )
        }

        let context = UICockpitContext(
            tools: toolCards,
            tools_present: !toolCards.isEmpty,
            selected_tool_id: selectedToolID,
            selected_action: selectedAction,
            selected_workspace_path: selectedWorkspacePath,
            selected_parameters_json: selectedParametersJSON,
            selected_input_artifacts_json: selectedInputArtifactsJSON,
            selected_allow_destructive_attr: selectedAllowDestructive ? "checked" : "",
            history_rows: historyRows,
            history_present: !historyRows.isEmpty,
            history_file: history.historyFile,
            notice: nonEmpty(req.query[String.self, at: "notice"]),
            error: nonEmpty(req.query[String.self, at: "error"])
        )

        return try await req.view.render("cockpit", context)
    }

    let runPilotage: @Sendable (Request) async throws -> Response = { req in
        do {
            let form = try req.content.decode(UICockpitRunForm.self)
            let toolID = form.tool_id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !toolID.isEmpty else {
                throw Abort(.badRequest, reason: "Le tool_id est requis.")
            }

            let parameters = try parseParametersJSON(form.parameters_json)
            let inputArtifacts = try parseInputArtifactsJSON(form.input_artifacts_json)
            let launchRequest = CockpitLaunchRequest(
                toolID: toolID,
                action: nonEmpty(form.action),
                correlationID: req.headers.first(name: "x-correlation-id"),
                workspacePath: nonEmpty(form.workspace_path),
                inputArtifacts: inputArtifacts,
                parameters: parameters,
                allowDestructive: parseBooleanFlag(form.allow_destructive, defaultValue: false)
            )

            let outcome = try await CockpitCanonicalLauncher.launch(launchRequest, logger: req.logger)
            let notice = "Exécution \(outcome.executionID) terminée avec statut \(outcome.result.status.rawValue)."
            return req.redirect(to: "/ui/pilotage?notice=\(urlQueryEncoded(notice))&tool=\(urlQueryEncoded(toolID))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec exécution pilotage." : abort.reason
            return req.redirect(to: "/ui/pilotage?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec exécution pilotage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/pilotage?error=\(urlQueryEncoded("Erreur interne pendant l'exécution du pilotage."))")
        }
    }

    app.get("ui", "tools") { req async throws -> Response in
        req.redirect(to: "/ui/pilotage")
    }
    app.get("u", "pilotage") { req async throws -> Response in
        req.redirect(to: "/ui/pilotage")
    }
    app.get("u", "cockpit") { req async throws -> Response in
        req.redirect(to: "/ui/cockpit")
    }

    app.get("ui", "cockpit", use: renderPilotageView)
    app.get("ui", "pilotage", use: renderPilotageView)
    app.on(.POST, "ui", "cockpit", "run", body: .collect(maxSize: "2mb"), use: runPilotage)
    app.on(.POST, "ui", "pilotage", "run", body: .collect(maxSize: "2mb"), use: runPilotage)
}

private func parseParametersJSON(_ raw: String?) throws -> [String: JSONValue] {
    guard let json = nonEmpty(raw) else {
        return [:]
    }
    guard let data = json.data(using: .utf8) else {
        throw Abort(.badRequest, reason: "Le JSON des paramètres est invalide (encodage).")
    }
    do {
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    } catch {
        throw Abort(.badRequest, reason: "Le JSON des paramètres est invalide: \(error.localizedDescription)")
    }
}

private func parseInputArtifactsJSON(_ raw: String?) throws -> [ArtifactDescriptor] {
    guard let json = nonEmpty(raw) else {
        return []
    }
    guard let data = json.data(using: .utf8) else {
        throw Abort(.badRequest, reason: "Le JSON input_artifacts est invalide (encodage).")
    }
    do {
        return try JSONDecoder().decode([ArtifactDescriptor].self, from: data)
    } catch {
        throw Abort(.badRequest, reason: "Le JSON input_artifacts est invalide: \(error.localizedDescription)")
    }
}

private func prettyJSONString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

private func parseBooleanFlag(_ raw: String?, defaultValue: Bool = false) -> Bool {
    guard let raw else { return defaultValue }
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off", "":
        return false
    default:
        return defaultValue
    }
}

private func uiStatusLabel(_ status: ToolStatus) -> String {
    switch status {
    case .queued:
        return "En file"
    case .running:
        return "En cours"
    case .succeeded:
        return "Succès"
    case .failed:
        return "Échec"
    case .needsReview:
        return "À revoir"
    case .cancelled:
        return "Annulé"
    case .notImplemented:
        return "Non implémenté"
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func urlQueryEncoded(_ value: String) -> String {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
