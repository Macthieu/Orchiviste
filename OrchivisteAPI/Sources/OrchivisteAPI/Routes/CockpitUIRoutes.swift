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
    let diagnostics_present: Bool
    let extraction_provenance: String
    let extraction_provenance_present: Bool
    let regles_source: String
    let regles_source_present: Bool
    let regles_bundle_version: String
    let regles_bundle_version_present: Bool
    let regles_module_version: String
    let regles_module_version_present: Bool
    let regles_rule_id: String
    let regles_rule_id_present: Bool
    let regles_fallback_reason: String
    let regles_fallback_reason_present: Bool
    let warnings_count: String
    let warnings_summary: String
    let warnings_present: Bool
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

private struct UICockpitHistoryDiagnostics: Sendable {
    var extractionProvenance: String?
    var reglesSource: String?
    var reglesBundleVersion: String?
    var reglesModuleVersion: String?
    var reglesRuleID: String?
    var reglesFallbackReason: String?
    var warnings: [String]

    static let empty = UICockpitHistoryDiagnostics(
        extractionProvenance: nil,
        reglesSource: nil,
        reglesBundleVersion: nil,
        reglesModuleVersion: nil,
        reglesRuleID: nil,
        reglesFallbackReason: nil,
        warnings: []
    )

    var hasDiagnostics: Bool {
        extractionProvenance != nil ||
        reglesSource != nil ||
        reglesBundleVersion != nil ||
        reglesModuleVersion != nil ||
        reglesRuleID != nil ||
        reglesFallbackReason != nil ||
        !warnings.isEmpty
    }
}

func registerCockpitUIRoutes(_ app: Application) {
    let buildPilotageContext: @Sendable (Request) async -> UICockpitContext = { req in
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
            let diagnostics = loadHistoryDiagnostics(for: entry, logger: req.logger)
            let warningSummary = summarizeWarnings(diagnostics.warnings)
            return UICockpitHistoryRow(
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
                result_file: entry.resultFile,
                diagnostics_present: diagnostics.hasDiagnostics,
                extraction_provenance: diagnostics.extractionProvenance ?? "-",
                extraction_provenance_present: diagnostics.extractionProvenance != nil,
                regles_source: diagnostics.reglesSource ?? "-",
                regles_source_present: diagnostics.reglesSource != nil,
                regles_bundle_version: diagnostics.reglesBundleVersion ?? "-",
                regles_bundle_version_present: diagnostics.reglesBundleVersion != nil,
                regles_module_version: diagnostics.reglesModuleVersion ?? "-",
                regles_module_version_present: diagnostics.reglesModuleVersion != nil,
                regles_rule_id: diagnostics.reglesRuleID ?? "-",
                regles_rule_id_present: diagnostics.reglesRuleID != nil,
                regles_fallback_reason: diagnostics.reglesFallbackReason ?? "-",
                regles_fallback_reason_present: diagnostics.reglesFallbackReason != nil,
                warnings_count: diagnostics.warnings.isEmpty ? "-" : String(diagnostics.warnings.count),
                warnings_summary: warningSummary ?? "-",
                warnings_present: !diagnostics.warnings.isEmpty
            )
        }

        return UICockpitContext(
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
            return req.redirect(to: "/ui/pilotage/lancer?notice=\(urlQueryEncoded(notice))&tool=\(urlQueryEncoded(toolID))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec exécution pilotage." : abort.reason
            return req.redirect(to: "/ui/pilotage/lancer?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec exécution pilotage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/pilotage/lancer?error=\(urlQueryEncoded("Erreur interne pendant l'exécution du pilotage."))")
        }
    }

    app.get("ui", "tools") { req async throws -> Response in
        req.redirect(to: "/ui/pilotage/catalogue")
    }
    app.get("u", "pilotage") { req async throws -> Response in
        req.redirect(to: "/ui/pilotage/catalogue")
    }
    app.get("u", "cockpit") { req async throws -> Response in
        req.redirect(to: "/ui/pilotage/catalogue")
    }
    app.get("ui", "pilotage") { req async throws -> Response in
        req.redirect(to: "/ui/pilotage/catalogue")
    }
    app.get("ui", "cockpit") { req async throws -> Response in
        req.redirect(to: "/ui/pilotage/catalogue")
    }

    app.get("ui", "pilotage", "catalogue") { req async throws -> View in
        let context = await buildPilotageContext(req)
        return try await req.view.render("pilotage_catalogue", context)
    }
    app.get("ui", "pilotage", "lancer") { req async throws -> View in
        let context = await buildPilotageContext(req)
        return try await req.view.render("pilotage_lancer", context)
    }
    app.get("ui", "pilotage", "historique") { req async throws -> View in
        let context = await buildPilotageContext(req)
        return try await req.view.render("pilotage_historique", context)
    }

    app.on(.POST, "ui", "cockpit", "run", body: .collect(maxSize: "2mb"), use: runPilotage)
    app.on(.POST, "ui", "pilotage", "run", body: .collect(maxSize: "2mb"), use: runPilotage)
}

private func loadHistoryDiagnostics(for entry: CockpitHistoryEntry, logger: Logger) -> UICockpitHistoryDiagnostics {
    guard let resultRoot = readJSONObject(atPath: entry.resultFile, logger: logger) else {
        return .empty
    }

    let metadata = resultRoot["metadata"] as? [String: Any] ?? [:]
    var warnings = extractWarningLabels(from: metadata["warnings"])

    var extractionProvenance = stringValue(from: metadata["extraction_provenance"])
    if let metadataArtifactPath = resolveArtifactPath(
        fromResultRoot: resultRoot,
        artifactID: "document_metadata",
        requiredKind: "metadata",
        relativeToFile: entry.resultFile
    ),
    let metadataRoot = readJSONObject(atPath: metadataArtifactPath, logger: logger) {
        let artifactProvenances = extractExtractionProvenances(fromMetadataPayload: metadataRoot)
        if extractionProvenance == nil, !artifactProvenances.isEmpty {
            extractionProvenance = artifactProvenances.joined(separator: ", ")
        }

        let artifactWarnings = extractWarnings(fromMetadataPayload: metadataRoot)
        if !artifactWarnings.isEmpty {
            warnings = artifactWarnings
        }
    }

    if warnings.isEmpty,
       let warningCount = intValue(from: metadata["warning_count"]),
       warningCount > 0 {
        warnings = Array(repeating: "warning_present", count: warningCount)
    }

    return UICockpitHistoryDiagnostics(
        extractionProvenance: extractionProvenance,
        reglesSource: stringValue(from: metadata["regles_source"]),
        reglesBundleVersion: stringValue(from: metadata["regles_bundle_version"]),
        reglesModuleVersion: stringValue(from: metadata["regles_module_version"]),
        reglesRuleID: stringValue(from: metadata["regles_rule_id"]),
        reglesFallbackReason: stringValue(from: metadata["regles_fallback_reason"]),
        warnings: warnings
    )
}

private func summarizeWarnings(_ warnings: [String]) -> String? {
    guard !warnings.isEmpty else {
        return nil
    }

    var counts: [String: Int] = [:]
    for warning in warnings {
        counts[warning, default: 0] += 1
    }

    let sortedWarnings = counts.keys.sorted()
    let summarized = sortedWarnings.map { warning in
        let count = counts[warning, default: 0]
        return count > 1 ? "\(warning) x\(count)" : warning
    }

    if summarized.count <= 3 {
        return summarized.joined(separator: ", ")
    }

    let prefix = summarized.prefix(3).joined(separator: ", ")
    return "\(prefix), +\(summarized.count - 3) autre(s)"
}

private func readJSONObject(atPath path: String, logger: Logger) -> [String: Any]? {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
    }

    do {
        let data = try Data(contentsOf: fileURL)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    } catch {
        logger.debug("Lecture JSON cockpit historique ignorée (best effort).", metadata: [
            "path": .string(fileURL.path),
            "error": .string(error.localizedDescription)
        ])
        return nil
    }
}

private func resolveArtifactPath(
    fromResultRoot root: [String: Any],
    artifactID: String,
    requiredKind: String?,
    relativeToFile resultFilePath: String
) -> String? {
    guard let artifacts = root["output_artifacts"] as? [[String: Any]] else {
        return nil
    }

    guard let artifact = artifacts.first(where: { artifact in
        guard stringValue(from: artifact["id"]) == artifactID else {
            return false
        }
        if let requiredKind {
            return stringValue(from: artifact["kind"]) == requiredKind
        }
        return true
    }),
    let uri = stringValue(from: artifact["uri"]) else {
        return nil
    }

    return resolvePath(uri, relativeToFile: resultFilePath)
}

private func resolvePath(_ rawValue: String, relativeToFile filePath: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed) {
        return url.path
    }
    if (trimmed as NSString).isAbsolutePath {
        return trimmed
    }

    let base = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    return base.appendingPathComponent(trimmed).standardizedFileURL.path
}

private func extractExtractionProvenances(fromMetadataPayload payload: [String: Any]) -> [String] {
    guard let documents = payload["documents"] as? [[String: Any]] else {
        return []
    }

    var orderedUnique: [String] = []
    var seen: Set<String> = []
    for document in documents {
        guard let provenance = stringValue(from: document["extraction_provenance"]) else {
            continue
        }
        if seen.insert(provenance).inserted {
            orderedUnique.append(provenance)
        }
    }
    return orderedUnique
}

private func extractWarnings(fromMetadataPayload payload: [String: Any]) -> [String] {
    var warnings = extractWarningLabels(from: payload["warnings"])

    if let documents = payload["documents"] as? [[String: Any]] {
        for document in documents {
            warnings.append(contentsOf: extractWarningLabels(from: document["warnings"]))
        }
    }

    return warnings
}

private func extractWarningLabels(from rawValue: Any?) -> [String] {
    guard let rawValue else {
        return []
    }

    if let text = stringValue(from: rawValue) {
        return [text]
    }

    guard let array = rawValue as? [Any] else {
        return []
    }

    return array.compactMap { item in
        if let text = stringValue(from: item) {
            return text
        }

        guard let object = item as? [String: Any] else {
            return nil
        }

        if let code = stringValue(from: object["code"]) {
            return code
        }

        return stringValue(from: object["message"])
    }
}

private func stringValue(from rawValue: Any?) -> String? {
    guard let rawValue = rawValue as? String else {
        return nil
    }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func intValue(from rawValue: Any?) -> Int? {
    if let int = rawValue as? Int {
        return int
    }
    if let number = rawValue as? NSNumber {
        return number.intValue
    }
    if let text = rawValue as? String {
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
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
