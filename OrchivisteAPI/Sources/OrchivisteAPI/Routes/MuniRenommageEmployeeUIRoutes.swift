import Fluent
import Foundation
import OrchivisteKitContracts
import Vapor

private struct UIMuniRenommageEmployeeForm: Content {
    let source_directory: String
    let destination_directory: String
    let source_directory_mode: String?
    let destination_directory_mode: String?
    let recursive: String?
    let include_hidden: String?
    let preview_execution_id: String?
    let operation: String
}

private struct UIMuniRenommageEmployeeRecentRun: Encodable {
    let execution_id: String
    let action_label: String
    let status_label: String
    let finished_at: String
    let summary: String
    let diagnostic_label: String
    let diagnostic_present: Bool
    let diagnostic_severity_class: String
    let view_url: String
}

private struct UIMuniRenommageEmployeeContext: Encodable {
    let source_directory: String
    let destination_directory: String
    let recursive_checked_attr: String
    let include_hidden_checked_attr: String
    let preview_execution_id: String
    let preview_execution_id_present: Bool
    let availability_label: String
    let availability_class: String
    let availability_reason: String
    let standard_profile_name: String
    let standard_profile_summary: String
    let apply_disabled_attr: String
    let apply_hint: String
    let apply_hint_present: Bool
    let result_present: Bool
    let result_execution_id: String
    let result_action_label: String
    let result_status_label: String
    let result_status_class: String
    let result_summary: String
    let result_finished_at: String
    let result_plan_digest: String
    let result_plan_digest_present: Bool
    let result_items_count: String
    let result_operations_count: String
    let result_warnings_count: String
    let result_collisions_count: String
    let result_existing_destinations_count: String
    let result_idempotent_count: String
    let result_diagnostic_present: Bool
    let result_diagnostic_label: String
    let result_diagnostic_severity_label: String
    let result_diagnostic_severity_class: String
    let result_diagnostic_cta: String
    let result_diagnostic_cta_present: Bool
    let recent_runs: [UIMuniRenommageEmployeeRecentRun]
    let recent_runs_present: Bool
    let technical_app_url: String
    let expert_launch_url: String
    let back_to_catalog_url: String
    let notice: String?
    let error: String?
}

private struct MuniRenommageEmployeeResultSnapshot {
    let executionID: String
    let actionLabel: String
    let statusLabel: String
    let statusClass: String
    let summary: String
    let finishedAt: String
    let planDigest: String?
    let plannedItemCount: Int?
    let plannedOperationCount: Int?
    let warningCount: Int?
    let collisionCount: Int?
    let existingDestinationCount: Int?
    let idempotentCount: Int?
    let diagnostic: RunDiagnosticRecord?
}

func registerMuniRenommageEmployeeUIRoutes(_ app: Application) {
    let buildContext: @Sendable (Request) async throws -> UIMuniRenommageEmployeeContext = { req in
        let sourceDirectory = nonEmptyEmployeePath(req.query[String.self, at: "source_directory"]) ?? ""
        let destinationDirectory = nonEmptyEmployeePath(req.query[String.self, at: "destination_directory"]) ?? ""
        let recursive = parseEmployeeFlag(req.query[String.self, at: "recursive"])
        let includeHidden = parseEmployeeFlag(req.query[String.self, at: "include_hidden"])
        let requestedExecutionID = nonEmptyEmployeePath(req.query[String.self, at: "execution_id"])
        let requestedPreviewExecutionID = nonEmptyEmployeePath(req.query[String.self, at: "preview_execution_id"])

        let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
        let runtimeTool = runtime.tools.first(where: { $0.descriptor.id == "MuniRenommage" })
        let isAvailable = runtimeTool?.isAvailable == true
        let availabilityLabel = isAvailable ? "Prêt" : "Indisponible"
        let availabilityClass = isAvailable ? "pill-ok" : "pill-warn"
        let availabilityReason = isAvailable
            ? "Le service de renommage standard est disponible."
            : (runtimeTool?.availabilityReason ?? "Disponibilité non déterminée.")

        let recentEntries = try await CockpitRegistryRepository.listRecentRuns(appID: "MuniRenommage", limit: 12, on: req.db)
        let selectedEntry = requestedExecutionID.flatMap { executionID in
            recentEntries.first(where: { $0.executionID == executionID })
        }

        var resultSnapshot: MuniRenommageEmployeeResultSnapshot?
        if let selectedEntry {
            let diagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: selectedEntry.executionID, on: req.db)
            let metadata = loadMuniRenommageResultMetadata(resultFilePath: selectedEntry.resultFile, logger: req.logger)
            resultSnapshot = MuniRenommageEmployeeResultSnapshot(
                executionID: selectedEntry.executionID,
                actionLabel: selectedEntry.action == "apply" ? "Application contrôlée" : "Prévisualisation",
                statusLabel: employeeStatusLabel(selectedEntry.status),
                statusClass: employeeStatusClass(selectedEntry.status),
                summary: employeeSummary(selectedEntry.summary, action: selectedEntry.action),
                finishedAt: selectedEntry.finishedAt,
                planDigest: metadata.planDigest,
                plannedItemCount: metadata.plannedItemCount,
                plannedOperationCount: metadata.plannedOperationCount,
                warningCount: metadata.warningCount,
                collisionCount: metadata.collisionCount,
                existingDestinationCount: metadata.existingDestinationCount,
                idempotentCount: metadata.idempotentCount,
                diagnostic: diagnostic
            )
        }

        let previewCandidateEntry = requestedPreviewExecutionID.flatMap { executionID in
            recentEntries.first(where: { $0.executionID == executionID })
        }
        let previewCandidateDiagnostic: RunDiagnosticRecord? = if let previewCandidateEntry {
            try await CockpitRegistryRepository.topDiagnostic(executionID: previewCandidateEntry.executionID, on: req.db)
        } else {
            nil
        }
        let previewCandidateMetadata: MuniRenommageResultMetadata = if let previewCandidateEntry {
            loadMuniRenommageResultMetadata(resultFilePath: previewCandidateEntry.resultFile, logger: req.logger)
        } else {
            MuniRenommageResultMetadata.empty
        }

        let applyState = buildEmployeeApplyState(
            previewEntry: previewCandidateEntry,
            metadata: previewCandidateMetadata,
            diagnostic: previewCandidateDiagnostic
        )

        var recentRuns: [UIMuniRenommageEmployeeRecentRun] = []
        recentRuns.reserveCapacity(min(recentEntries.count, 6))
        for entry in recentEntries.prefix(6) {
            let diagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: entry.executionID, on: req.db)
            recentRuns.append(UIMuniRenommageEmployeeRecentRun(
                execution_id: entry.executionID,
                action_label: entry.action == "apply" ? "Application" : "Prévisualisation",
                status_label: employeeStatusLabel(entry.status),
                finished_at: entry.finishedAt,
                summary: employeeSummary(entry.summary, action: entry.action),
                diagnostic_label: diagnostic?.label ?? "Aucun diagnostic prioritaire",
                diagnostic_present: diagnostic != nil,
                diagnostic_severity_class: diagnosticSeverityClass(diagnostic?.severity),
                view_url: employeeMuniRenommagePageURL(
                    sourceDirectory: sourceDirectory,
                    destinationDirectory: destinationDirectory,
                    recursive: recursive,
                    includeHidden: includeHidden,
                    executionID: entry.executionID,
                    previewExecutionID: entry.action == "preview"
                        ? entry.executionID
                        : requestedPreviewExecutionID
                )
            ))
        }

        return UIMuniRenommageEmployeeContext(
            source_directory: sourceDirectory,
            destination_directory: destinationDirectory,
            recursive_checked_attr: recursive ? "checked" : "",
            include_hidden_checked_attr: includeHidden ? "checked" : "",
            preview_execution_id: requestedPreviewExecutionID ?? "",
            preview_execution_id_present: requestedPreviewExecutionID != nil,
            availability_label: availabilityLabel,
            availability_class: availabilityClass,
            availability_reason: availabilityReason,
            standard_profile_name: "Profil standard Orchiviste",
            standard_profile_summary: "Nettoyage des espaces, normalisation Unicode et classement vers le dossier destination choisi.",
            apply_disabled_attr: applyState.isApplyEnabled ? "" : "disabled",
            apply_hint: applyState.message ?? "",
            apply_hint_present: applyState.message != nil,
            result_present: resultSnapshot != nil,
            result_execution_id: resultSnapshot?.executionID ?? "",
            result_action_label: resultSnapshot?.actionLabel ?? "",
            result_status_label: resultSnapshot?.statusLabel ?? "",
            result_status_class: resultSnapshot?.statusClass ?? "status-info",
            result_summary: resultSnapshot?.summary ?? "",
            result_finished_at: resultSnapshot?.finishedAt ?? "",
            result_plan_digest: resultSnapshot?.planDigest ?? "",
            result_plan_digest_present: resultSnapshot?.planDigest != nil,
            result_items_count: stringOrDash(resultSnapshot?.plannedItemCount),
            result_operations_count: stringOrDash(resultSnapshot?.plannedOperationCount),
            result_warnings_count: stringOrDash(resultSnapshot?.warningCount),
            result_collisions_count: stringOrDash(resultSnapshot?.collisionCount),
            result_existing_destinations_count: stringOrDash(resultSnapshot?.existingDestinationCount),
            result_idempotent_count: stringOrDash(resultSnapshot?.idempotentCount),
            result_diagnostic_present: resultSnapshot?.diagnostic != nil,
            result_diagnostic_label: resultSnapshot?.diagnostic?.label ?? "",
            result_diagnostic_severity_label: diagnosticSeverityLabel(resultSnapshot?.diagnostic?.severity),
            result_diagnostic_severity_class: diagnosticSeverityClass(resultSnapshot?.diagnostic?.severity),
            result_diagnostic_cta: employeeDiagnosticCTA(resultSnapshot?.diagnostic?.cta),
            result_diagnostic_cta_present: resultSnapshot?.diagnostic?.cta != nil,
            recent_runs: recentRuns,
            recent_runs_present: !recentRuns.isEmpty,
            technical_app_url: "/ui/muni/apps/MuniRenommage",
            expert_launch_url: "/ui/pilotage/lancer?tool=MuniRenommage",
            back_to_catalog_url: "/ui/pilotage/catalogue",
            notice: nonEmptyEmployeePath(req.query[String.self, at: "notice"]),
            error: nonEmptyEmployeePath(req.query[String.self, at: "error"])
        )
    }

    app.get("ui", "muni", "apps", "MuniRenommage", "employe") { req async throws -> View in
        let context = try await buildContext(req)
        return try await req.view.render("muni_renommage_employee", context)
    }

    app.on(.POST, "ui", "muni", "apps", "MuniRenommage", "employe", "run", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        let form = try req.content.decode(UIMuniRenommageEmployeeForm.self)
        let sourceDirectory = try validatedDirectoryPath(form.source_directory, label: "source")
        let destinationDirectory = try validatedDirectoryPath(form.destination_directory, label: "destination")
        let recursive = parseEmployeeFlag(form.recursive)
        let includeHidden = parseEmployeeFlag(form.include_hidden)
        let operation = normalizedEmployeeOperation(form.operation)

        do {
            let runtimeConfig = CockpitConfigLoader.load(logger: req.logger)
            let presetURL = try writeEmployeePresetFile(
                sourceDirectory: sourceDirectory,
                destinationDirectory: destinationDirectory,
                runtimeConfig: runtimeConfig
            )

            var parameters: [String: JSONValue] = [
                "preset_path": .string(presetURL.path),
                "directory_path": .string(sourceDirectory),
                "recursive": .bool(recursive),
                "include_hidden": .bool(includeHidden),
                "dry_run": .bool(operation == .preview),
                "confirm_apply": .bool(operation == .apply)
            ]

            var allowDestructive = false
            var previewExecutionIDForRedirect = nonEmptyEmployeePath(form.preview_execution_id)

            if operation == .apply {
                let previewReferenceID = try requiredPreviewExecutionID(form.preview_execution_id)
                let previewEntries = try await CockpitRegistryRepository.listRecentRuns(appID: "MuniRenommage", limit: 25, on: req.db)
                guard let previewEntry = previewEntries.first(where: { $0.executionID == previewReferenceID }) else {
                    throw Abort(.badRequest, reason: "Prévisualisation de référence introuvable. Relancez une prévisualisation.")
                }
                guard previewEntry.action == "preview" else {
                    throw Abort(.badRequest, reason: "L'application requiert une prévisualisation comme référence.")
                }

                let previewDiagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: previewEntry.executionID, on: req.db)
                if previewDiagnostic?.severity == "blocking" {
                    throw Abort(
                        .badRequest,
                        reason: "Application bloquée: la prévisualisation de référence contient un diagnostic bloquant."
                    )
                }

                let previewMetadata = loadMuniRenommageResultMetadata(resultFilePath: previewEntry.resultFile, logger: req.logger)
                guard let planDigest = previewMetadata.planDigest, !planDigest.isEmpty else {
                    throw Abort(.badRequest, reason: "Le preview de référence ne contient pas de digest exploitable.")
                }

                parameters["expected_plan_digest"] = .string(planDigest)
                allowDestructive = true
                previewExecutionIDForRedirect = previewEntry.executionID
            }

            let launchRequest = CockpitLaunchRequest(
                toolID: "MuniRenommage",
                action: operation.rawValue,
                correlationID: req.headers.first(name: "x-correlation-id"),
                workspacePath: nil,
                inputArtifacts: [],
                parameters: parameters,
                allowDestructive: allowDestructive
            )

            let outcome = try await CockpitCanonicalLauncher.launch(launchRequest, on: req.db, logger: req.logger)
            let notice = operation == .preview
                ? "Prévisualisation \(outcome.executionID) terminée."
                : "Application \(outcome.executionID) terminée."

            let redirect = employeeMuniRenommagePageURL(
                sourceDirectory: sourceDirectory,
                destinationDirectory: destinationDirectory,
                recursive: recursive,
                includeHidden: includeHidden,
                executionID: outcome.executionID,
                previewExecutionID: operation == .preview ? outcome.executionID : previewExecutionIDForRedirect,
                notice: notice
            )
            return req.redirect(to: redirect)
        } catch let abort as AbortError {
            return req.redirect(
                to: employeeMuniRenommagePageURL(
                    sourceDirectory: sourceDirectory,
                    destinationDirectory: destinationDirectory,
                    recursive: recursive,
                    includeHidden: includeHidden,
                    executionID: nil,
                    previewExecutionID: nonEmptyEmployeePath(form.preview_execution_id),
                    error: abort.reason.isEmpty ? "Échec exécution MuniRenommage." : abort.reason
                )
            )
        } catch {
            req.logger.error("Échec façade employé MuniRenommage.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(
                to: employeeMuniRenommagePageURL(
                    sourceDirectory: sourceDirectory,
                    destinationDirectory: destinationDirectory,
                    recursive: recursive,
                    includeHidden: includeHidden,
                    executionID: nil,
                    previewExecutionID: nonEmptyEmployeePath(form.preview_execution_id),
                    error: "Erreur interne pendant l'exécution de MuniRenommage."
                )
            )
        }
    }
}

private enum MuniRenommageEmployeeOperation: String {
    case preview
    case apply
}

private struct MuniRenommageResultMetadata {
    let planDigest: String?
    let plannedItemCount: Int?
    let plannedOperationCount: Int?
    let warningCount: Int?
    let collisionCount: Int?
    let existingDestinationCount: Int?
    let idempotentCount: Int?

    static let empty = MuniRenommageResultMetadata(
        planDigest: nil,
        plannedItemCount: nil,
        plannedOperationCount: nil,
        warningCount: nil,
        collisionCount: nil,
        existingDestinationCount: nil,
        idempotentCount: nil
    )
}

private struct EmployeeApplyState {
    let isApplyEnabled: Bool
    let message: String?
}

private func buildEmployeeApplyState(
    previewEntry: CockpitHistoryEntry?,
    metadata: MuniRenommageResultMetadata,
    diagnostic: RunDiagnosticRecord?
) -> EmployeeApplyState {
    guard let previewEntry else {
        return EmployeeApplyState(
            isApplyEnabled: false,
            message: "Prévisualisez d'abord le dossier pour verrouiller un plan avant l'application."
        )
    }

    guard previewEntry.action == "preview" else {
        return EmployeeApplyState(
            isApplyEnabled: false,
            message: "La référence courante n'est pas une prévisualisation. Sélectionnez une prévisualisation récente."
        )
    }

    if diagnostic?.severity == "blocking" {
        return EmployeeApplyState(
            isApplyEnabled: false,
            message: "Application bloquée: la prévisualisation de référence contient un diagnostic bloquant."
        )
    }

    guard let planDigest = metadata.planDigest, !planDigest.isEmpty else {
        return EmployeeApplyState(
            isApplyEnabled: false,
            message: "Application indisponible: aucun digest valide n'a été produit par la prévisualisation."
        )
    }

    return EmployeeApplyState(
        isApplyEnabled: true,
        message: "L'application utilisera le plan validé par la prévisualisation \(previewEntry.executionID) (\(planDigest))."
    )
}

private func employeeMuniRenommagePageURL(
    sourceDirectory: String,
    destinationDirectory: String,
    recursive: Bool,
    includeHidden: Bool,
    executionID: String?,
    previewExecutionID: String?,
    notice: String? = nil,
    error: String? = nil
) -> String {
    var params: [String] = []
    if !sourceDirectory.isEmpty {
        params.append("source_directory=\(employeeURLQueryEncoded(sourceDirectory))")
    }
    if !destinationDirectory.isEmpty {
        params.append("destination_directory=\(employeeURLQueryEncoded(destinationDirectory))")
    }
    if recursive {
        params.append("recursive=true")
    }
    if includeHidden {
        params.append("include_hidden=true")
    }
    if let executionID {
        params.append("execution_id=\(employeeURLQueryEncoded(executionID))")
    }
    if let previewExecutionID {
        params.append("preview_execution_id=\(employeeURLQueryEncoded(previewExecutionID))")
    }
    if let notice {
        params.append("notice=\(employeeURLQueryEncoded(notice))")
    }
    if let error {
        params.append("error=\(employeeURLQueryEncoded(error))")
    }

    if params.isEmpty {
        return "/ui/muni/apps/MuniRenommage/employe"
    }
    return "/ui/muni/apps/MuniRenommage/employe?\(params.joined(separator: "&"))"
}

private func normalizedEmployeeOperation(_ rawValue: String) -> MuniRenommageEmployeeOperation {
    rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "apply" ? .apply : .preview
}

private func requiredPreviewExecutionID(_ rawValue: String?) throws -> String {
    guard let executionID = nonEmptyEmployeePath(rawValue) else {
        throw Abort(.badRequest, reason: "L'application requiert une prévisualisation de référence. Lancez d'abord une prévisualisation.")
    }
    return executionID
}

private func writeEmployeePresetFile(
    sourceDirectory: String,
    destinationDirectory: String,
    runtimeConfig: CockpitConfig
) throws -> URL {
    let basePresetURL = employeeBasePresetURL()
    guard FileManager.default.fileExists(atPath: basePresetURL.path) else {
        throw Abort(
            .internalServerError,
            reason: "Preset employé MuniRenommage introuvable dans la configuration Orchiviste."
        )
    }

    let data = try Data(contentsOf: basePresetURL)
    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var preset = root["preset"] as? [String: Any],
          var rules = preset["rules"] as? [String: Any] else {
        throw Abort(.internalServerError, reason: "Preset employé MuniRenommage invalide.")
    }

    var destination = rules["destination"] as? [String: Any] ?? [:]
    destination["enabled"] = true
    destination["url"] = URL(fileURLWithPath: destinationDirectory, isDirectory: true).absoluteString
    destination["copyInsteadOfMove"] = false
    rules["destination"] = destination

    preset["rules"] = rules
    root["preset"] = preset

    let presetsDirectory = URL(fileURLWithPath: runtimeConfig.runtimeDirectory, isDirectory: true)
        .appendingPathComponent("employee-presets", isDirectory: true)
    try FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)

    let sourceToken = sanitizedEmployeeFileComponent(URL(fileURLWithPath: sourceDirectory).lastPathComponent)
    let fileURL = presetsDirectory.appendingPathComponent(
        "munirenommage-\(sourceToken)-\(UUID().uuidString).json"
    )
    let rendered = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    try rendered.write(to: fileURL, options: [.atomic])
    return fileURL
}

private func employeeBasePresetURL() -> URL {
    ConfigLoader.baseDir().appendingPathComponent("cockpit/munirenommage-employee-base.json")
}

private func sanitizedEmployeeFileComponent(_ rawValue: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let compact = rawValue.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let rendered = String(compact).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return rendered.isEmpty ? "run" : rendered
}

private func validatedDirectoryPath(_ rawValue: String, label: String) throws -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw Abort(.badRequest, reason: "Le dossier \(label) est requis.")
    }

    let url = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw Abort(.badRequest, reason: "Le dossier \(label) doit exister et être accessible.")
    }
    return url.path
}

private func loadMuniRenommageResultMetadata(resultFilePath: String, logger: Logger) -> MuniRenommageResultMetadata {
    guard let resultRoot = employeeReadJSONObject(atPath: resultFilePath, logger: logger) else {
        return .empty
    }
    let metadata = resultRoot["metadata"] as? [String: Any] ?? [:]
    return MuniRenommageResultMetadata(
        planDigest: employeeStringValue(from: metadata["plan_digest"]),
        plannedItemCount: employeeIntValue(from: metadata["planned_item_count"]),
        plannedOperationCount: employeeIntValue(from: metadata["planned_operation_count"]),
        warningCount: employeeIntValue(from: metadata["warning_count"]),
        collisionCount: employeeIntValue(from: metadata["collision_count"]),
        existingDestinationCount: employeeIntValue(from: metadata["existing_destination_count"]),
        idempotentCount: employeeIntValue(from: metadata["idempotent_count"])
    )
}

private func employeeReadJSONObject(atPath path: String, logger: Logger) -> [String: Any]? {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
    }

    do {
        let data = try Data(contentsOf: fileURL)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    } catch {
        logger.debug("Lecture JSON MuniRenommage employé ignorée.", metadata: [
            "path": .string(fileURL.path),
            "error": .string(error.localizedDescription)
        ])
        return nil
    }
}

private func employeeStringValue(from rawValue: Any?) -> String? {
    guard let rawValue = rawValue as? String else {
        return nil
    }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func employeeIntValue(from rawValue: Any?) -> Int? {
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

private func parseEmployeeFlag(_ rawValue: String?) -> Bool {
    guard let rawValue else { return false }
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    default:
        return false
    }
}

private func nonEmptyEmployeePath(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func employeeURLQueryEncoded(_ value: String) -> String {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func employeeStatusLabel(_ status: ToolStatus) -> String {
    switch status {
    case .succeeded:
        return "Succès"
    case .needsReview:
        return "À revoir"
    case .failed:
        return "Échec"
    case .queued:
        return "En file"
    case .running:
        return "En cours"
    case .cancelled:
        return "Annulé"
    case .notImplemented:
        return "Non implémenté"
    }
}

private func employeeStatusClass(_ status: ToolStatus) -> String {
    switch status {
    case .succeeded:
        return "status-success"
    case .needsReview:
        return "status-warning"
    case .failed:
        return "status-danger"
    default:
        return "status-info"
    }
}

private func employeeSummary(_ rawSummary: String?, action: String) -> String {
    let trimmed = rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty {
        return "Aucun résumé disponible."
    }

    switch trimmed {
    case "Preview completed.":
        return "Prévisualisation terminée."
    case "Apply request executed in dry-run mode.":
        return "Prévisualisation terminée sur une demande d'application."
    case "Apply completed successfully.":
        return "Application terminée avec succès."
    case "Apply completed with errors.":
        return "Application terminée avec erreurs."
    case "Preset is invalid for execution.":
        return "Le profil standard n'est pas valide pour cette exécution."
    default:
        return action == "apply" ? trimmed.replacingOccurrences(of: "Apply", with: "Application") : trimmed
    }
}

private func diagnosticSeverityLabel(_ severity: String?) -> String {
    switch severity {
    case "blocking":
        return "Blocking"
    case "warning":
        return "Warning"
    default:
        return "Info"
    }
}

private func diagnosticSeverityClass(_ severity: String?) -> String {
    switch severity {
    case "blocking":
        return "diag-blocking"
    case "warning":
        return "diag-warning"
    default:
        return "diag-info"
    }
}

private func employeeDiagnosticCTA(_ rawCTA: String?) -> String {
    switch rawCTA?.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "Re-preview":
        return "Relancer une prévisualisation"
    default:
        return rawCTA ?? ""
    }
}

private func stringOrDash(_ value: Int?) -> String {
    value.map(String.init) ?? "-"
}
