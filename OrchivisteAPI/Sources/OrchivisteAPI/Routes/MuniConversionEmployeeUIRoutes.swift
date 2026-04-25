import Fluent
import Foundation
import OrchivisteKitContracts
import Vapor

private struct UIMuniConversionEmployeeForm: Content {
    let source_directory: String
    let destination_directory: String?
    let source_directory_mode: String?
    let destination_directory_mode: String?
    let use_separate_destination: String?
    let include_subdirectories: String?
    let dry_run: String?
    let collision_policy: String?
    let profile_id: String
    let operation: String
}

private struct UIMuniConversionProfileOption: Encodable {
    let id: String
    let label: String
    let selected_attr: String
}

private struct UIMuniConversionCollisionOption: Encodable {
    let id: String
    let label: String
    let selected_attr: String
}

private struct UIMuniConversionEmployeeRecentRun: Encodable {
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

private struct UIMuniConversionEmployeeContext: Encodable {
    let source_directory: String
    let destination_directory: String
    let use_separate_destination_checked_attr: String
    let include_subdirectories_checked_attr: String
    let dry_run_checked_attr: String
    let availability_label: String
    let availability_class: String
    let availability_reason: String
    let profiles: [UIMuniConversionProfileOption]
    let collision_options: [UIMuniConversionCollisionOption]
    let result_present: Bool
    let result_execution_id: String
    let result_action_label: String
    let result_status_label: String
    let result_status_class: String
    let result_summary: String
    let result_finished_at: String
    let result_source_path: String
    let result_output_root_path: String
    let result_profile_id: String
    let result_total_scanned: String
    let result_total_matched: String
    let result_converted: String
    let result_simulated: String
    let result_ignored: String
    let result_skipped_existing: String
    let result_errors: String
    let result_diagnostic_present: Bool
    let result_diagnostic_label: String
    let result_diagnostic_severity_label: String
    let result_diagnostic_severity_class: String
    let recent_runs: [UIMuniConversionEmployeeRecentRun]
    let recent_runs_present: Bool
    let technical_app_url: String
    let expert_launch_url: String
    let back_to_catalog_url: String
    let notice: String?
    let error: String?
}

private struct MuniConversionResultMetadata {
    let sourcePath: String?
    let outputRootPath: String?
    let dryRun: Bool?
    let profileID: String?
    let totalScanned: Int?
    let totalMatched: Int?
    let converted: Int?
    let simulated: Int?
    let ignored: Int?
    let skippedExisting: Int?
    let errors: Int?

    static let empty = MuniConversionResultMetadata(
        sourcePath: nil,
        outputRootPath: nil,
        dryRun: nil,
        profileID: nil,
        totalScanned: nil,
        totalMatched: nil,
        converted: nil,
        simulated: nil,
        ignored: nil,
        skippedExisting: nil,
        errors: nil
    )
}

private struct MuniConversionResultSnapshot {
    let executionID: String
    let actionLabel: String
    let statusLabel: String
    let statusClass: String
    let summary: String
    let finishedAt: String
    let metadata: MuniConversionResultMetadata
    let diagnostic: RunDiagnosticRecord?
}

func registerMuniConversionEmployeeUIRoutes(_ app: Application) {
    let buildContext: @Sendable (Request) async throws -> UIMuniConversionEmployeeContext = { req in
        let sourceDirectory = nonEmptyMuniConversionValue(req.query[String.self, at: "source_directory"]) ?? ""
        let destinationDirectory = nonEmptyMuniConversionValue(req.query[String.self, at: "destination_directory"]) ?? ""
        let useSeparateDestination = parseMuniConversionFlag(req.query[String.self, at: "use_separate_destination"])
            || !destinationDirectory.isEmpty
        let includeSubdirectories = parseMuniConversionFlag(req.query[String.self, at: "include_subdirectories"])
        let dryRun = parseMuniConversionFlag(req.query[String.self, at: "dry_run"], defaultValue: true)
        let selectedProfileID = normalizedMuniConversionProfileID(req.query[String.self, at: "profile_id"])
        let selectedCollisionPolicy = normalizedMuniConversionCollisionPolicy(req.query[String.self, at: "collision_policy"])
        let requestedExecutionID = nonEmptyMuniConversionValue(req.query[String.self, at: "execution_id"])

        let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
        let runtimeTool = runtime.tools.first(where: { $0.descriptor.id == "MuniConversion" })
        let isAvailable = runtimeTool?.isAvailable == true
        let availabilityLabel = isAvailable ? "Prêt" : "Indisponible"
        let availabilityClass = isAvailable ? "pill-ok" : "pill-warn"
        let availabilityReason = isAvailable
            ? "Le service de conversion documentaire est disponible."
            : (runtimeTool?.availabilityReason ?? "Disponibilité non déterminée.")

        let recentEntries = try await CockpitRegistryRepository.listRecentRuns(appID: "MuniConversion", limit: 12, on: req.db)
        let selectedEntry = requestedExecutionID.flatMap { executionID in
            recentEntries.first(where: { $0.executionID == executionID })
        }

        var resultSnapshot: MuniConversionResultSnapshot?
        if let selectedEntry {
            let diagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: selectedEntry.executionID, on: req.db)
            let metadata = loadMuniConversionResultMetadata(resultFilePath: selectedEntry.resultFile, logger: req.logger)
            resultSnapshot = MuniConversionResultSnapshot(
                executionID: selectedEntry.executionID,
                actionLabel: selectedEntry.action == "convert" ? "Conversion" : "Analyse",
                statusLabel: muniConversionStatusLabel(selectedEntry.status),
                statusClass: muniConversionStatusClass(selectedEntry.status),
                summary: muniConversionSummary(selectedEntry.summary, action: selectedEntry.action, metadata: metadata),
                finishedAt: selectedEntry.finishedAt,
                metadata: metadata,
                diagnostic: diagnostic
            )
        }

        var recentRuns: [UIMuniConversionEmployeeRecentRun] = []
        recentRuns.reserveCapacity(min(recentEntries.count, 6))
        for entry in recentEntries.prefix(6) {
            let diagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: entry.executionID, on: req.db)
            recentRuns.append(UIMuniConversionEmployeeRecentRun(
                execution_id: entry.executionID,
                action_label: entry.action == "convert" ? "Conversion" : "Analyse",
                status_label: muniConversionStatusLabel(entry.status),
                finished_at: entry.finishedAt,
                summary: muniConversionSummary(entry.summary, action: entry.action, metadata: .empty),
                diagnostic_label: diagnostic?.label ?? "Aucun diagnostic prioritaire",
                diagnostic_present: diagnostic != nil,
                diagnostic_severity_class: muniConversionDiagnosticSeverityClass(diagnostic?.severity),
                view_url: employeeMuniConversionPageURL(
                    sourceDirectory: sourceDirectory,
                    destinationDirectory: destinationDirectory,
                    useSeparateDestination: useSeparateDestination,
                    includeSubdirectories: includeSubdirectories,
                    dryRun: dryRun,
                    profileID: selectedProfileID,
                    collisionPolicy: selectedCollisionPolicy,
                    executionID: entry.executionID
                )
            ))
        }

        return UIMuniConversionEmployeeContext(
            source_directory: sourceDirectory,
            destination_directory: destinationDirectory,
            use_separate_destination_checked_attr: useSeparateDestination ? "checked" : "",
            include_subdirectories_checked_attr: includeSubdirectories ? "checked" : "",
            dry_run_checked_attr: dryRun ? "checked" : "",
            availability_label: availabilityLabel,
            availability_class: availabilityClass,
            availability_reason: availabilityReason,
            profiles: muniConversionProfileOptions(selectedID: selectedProfileID),
            collision_options: muniConversionCollisionOptions(selectedID: selectedCollisionPolicy),
            result_present: resultSnapshot != nil,
            result_execution_id: resultSnapshot?.executionID ?? "",
            result_action_label: resultSnapshot?.actionLabel ?? "",
            result_status_label: resultSnapshot?.statusLabel ?? "",
            result_status_class: resultSnapshot?.statusClass ?? "status-info",
            result_summary: resultSnapshot?.summary ?? "",
            result_finished_at: resultSnapshot?.finishedAt ?? "",
            result_source_path: resultSnapshot?.metadata.sourcePath ?? "-",
            result_output_root_path: resultSnapshot?.metadata.outputRootPath ?? "-",
            result_profile_id: resultSnapshot?.metadata.profileID ?? "-",
            result_total_scanned: muniConversionStringOrDash(resultSnapshot?.metadata.totalScanned),
            result_total_matched: muniConversionStringOrDash(resultSnapshot?.metadata.totalMatched),
            result_converted: muniConversionStringOrDash(resultSnapshot?.metadata.converted),
            result_simulated: muniConversionStringOrDash(resultSnapshot?.metadata.simulated),
            result_ignored: muniConversionStringOrDash(resultSnapshot?.metadata.ignored),
            result_skipped_existing: muniConversionStringOrDash(resultSnapshot?.metadata.skippedExisting),
            result_errors: muniConversionStringOrDash(resultSnapshot?.metadata.errors),
            result_diagnostic_present: resultSnapshot?.diagnostic != nil,
            result_diagnostic_label: resultSnapshot?.diagnostic?.label ?? "",
            result_diagnostic_severity_label: muniConversionDiagnosticSeverityLabel(resultSnapshot?.diagnostic?.severity),
            result_diagnostic_severity_class: muniConversionDiagnosticSeverityClass(resultSnapshot?.diagnostic?.severity),
            recent_runs: recentRuns,
            recent_runs_present: !recentRuns.isEmpty,
            technical_app_url: "/ui/muni/apps/MuniConversion",
            expert_launch_url: "/ui/pilotage/lancer?tool=MuniConversion",
            back_to_catalog_url: "/ui/pilotage/catalogue",
            notice: nonEmptyMuniConversionValue(req.query[String.self, at: "notice"]),
            error: nonEmptyMuniConversionValue(req.query[String.self, at: "error"])
        )
    }

    app.get("ui", "muni", "apps", "MuniConversion", "employe") { req async throws -> View in
        let context = try await buildContext(req)
        return try await req.view.render("muni_conversion_employee", context)
    }

    app.on(.POST, "ui", "muni", "apps", "MuniConversion", "employe", "run", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        let form = try req.content.decode(UIMuniConversionEmployeeForm.self)
        let includeSubdirectories = parseMuniConversionFlag(form.include_subdirectories)
        let dryRun = parseMuniConversionFlag(form.dry_run)
        let profileID = normalizedMuniConversionProfileID(form.profile_id)
        let collisionPolicy = normalizedMuniConversionCollisionPolicy(form.collision_policy)
        let operation = normalizedMuniConversionOperation(form.operation)
        let useSeparateDestination = parseMuniConversionFlag(form.use_separate_destination)
            || nonEmptyMuniConversionValue(form.destination_directory) != nil

        do {
            let sourceDirectory = try validatedMuniConversionDirectoryPath(form.source_directory, label: "source")
            let destinationDirectory = try validatedOptionalMuniConversionDestination(
                form.destination_directory,
                useSeparateDestination: useSeparateDestination
            )
            let effectiveDryRun = operation == "analyze" ? true : dryRun
            let confirmConvert = operation == "convert" && !effectiveDryRun

            var parameters: [String: JSONValue] = [
                "source_path": .string(sourceDirectory),
                "profile_id": .string(profileID),
                "include_subdirectories": .bool(includeSubdirectories),
                "ignore_hidden_files": .bool(true),
                "preserve_relative_structure": .bool(false),
                "collision_policy": .string(collisionPolicy),
                "dry_run": .bool(effectiveDryRun),
                "confirm_convert": .bool(confirmConvert)
            ]
            if let destinationDirectory {
                parameters["output_path"] = .string(destinationDirectory)
            }

            let launchRequest = CockpitLaunchRequest(
                toolID: "MuniConversion",
                action: operation,
                correlationID: req.headers.first(name: "x-correlation-id"),
                workspacePath: nil,
                inputArtifacts: [],
                parameters: parameters,
                allowDestructive: confirmConvert
            )

            let outcome = try await CockpitCanonicalLauncher.launch(launchRequest, on: req.db, logger: req.logger)
            let notice = operation == "analyze"
                ? "Analyse \(outcome.executionID) terminée."
                : (effectiveDryRun
                    ? "Simulation de conversion \(outcome.executionID) terminée."
                    : "Conversion \(outcome.executionID) terminée.")

            return req.redirect(to: employeeMuniConversionPageURL(
                sourceDirectory: sourceDirectory,
                destinationDirectory: destinationDirectory ?? "",
                useSeparateDestination: destinationDirectory != nil,
                includeSubdirectories: includeSubdirectories,
                dryRun: dryRun,
                profileID: profileID,
                collisionPolicy: collisionPolicy,
                executionID: outcome.executionID,
                notice: notice
            ))
        } catch let abort as AbortError {
            return req.redirect(to: employeeMuniConversionPageURL(
                sourceDirectory: form.source_directory,
                destinationDirectory: form.destination_directory ?? "",
                useSeparateDestination: useSeparateDestination,
                includeSubdirectories: includeSubdirectories,
                dryRun: dryRun,
                profileID: profileID,
                collisionPolicy: collisionPolicy,
                executionID: nil,
                error: abort.reason.isEmpty ? "Échec exécution MuniConversion." : abort.reason
            ))
        } catch {
            req.logger.error("Échec façade employé MuniConversion.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: employeeMuniConversionPageURL(
                sourceDirectory: form.source_directory,
                destinationDirectory: form.destination_directory ?? "",
                useSeparateDestination: useSeparateDestination,
                includeSubdirectories: includeSubdirectories,
                dryRun: dryRun,
                profileID: profileID,
                collisionPolicy: collisionPolicy,
                executionID: nil,
                error: "Erreur interne pendant l'exécution de MuniConversion."
            ))
        }
    }
}

private func muniConversionProfileOptions(selectedID: String) -> [UIMuniConversionProfileOption] {
    [
        ("docx_to_pdf", "DOCX -> PDF"),
        ("doc_to_pdf", "DOC -> PDF"),
        ("xlsx_to_pdf", "XLSX -> PDF"),
        ("xls_to_pdf", "XLS -> PDF"),
        ("pptx_to_pdf", "PPTX -> PDF"),
        ("ppt_to_pdf", "PPT -> PDF"),
        ("rtf_to_pdf", "RTF -> PDF"),
        ("txt_to_pdf", "TXT -> PDF"),
        ("odt_to_pdf", "ODT -> PDF"),
        ("ods_to_pdf", "ODS -> PDF"),
        ("odp_to_pdf", "ODP -> PDF")
    ].map { id, label in
        UIMuniConversionProfileOption(
            id: id,
            label: label,
            selected_attr: id == selectedID ? "selected" : ""
        )
    }
}

private func muniConversionCollisionOptions(selectedID: String) -> [UIMuniConversionCollisionOption] {
    [
        ("skip_existing", "Ignorer si le fichier existe"),
        ("rename_with_suffix", "Renommer avec suffixe"),
        ("overwrite", "Écraser le fichier existant")
    ].map { id, label in
        UIMuniConversionCollisionOption(
            id: id,
            label: label,
            selected_attr: id == selectedID ? "selected" : ""
        )
    }
}

private func employeeMuniConversionPageURL(
    sourceDirectory: String,
    destinationDirectory: String,
    useSeparateDestination: Bool,
    includeSubdirectories: Bool,
    dryRun: Bool,
    profileID: String,
    collisionPolicy: String,
    executionID: String?,
    notice: String? = nil,
    error: String? = nil
) -> String {
    var params: [String] = []
    if !sourceDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        params.append("source_directory=\(muniConversionURLQueryEncoded(sourceDirectory))")
    }
    if !destinationDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        params.append("destination_directory=\(muniConversionURLQueryEncoded(destinationDirectory))")
    }
    if useSeparateDestination {
        params.append("use_separate_destination=true")
    }
    if includeSubdirectories {
        params.append("include_subdirectories=true")
    }
    params.append("dry_run=\(dryRun ? "true" : "false")")
    params.append("profile_id=\(muniConversionURLQueryEncoded(profileID))")
    params.append("collision_policy=\(muniConversionURLQueryEncoded(collisionPolicy))")
    if let executionID {
        params.append("execution_id=\(muniConversionURLQueryEncoded(executionID))")
    }
    if let notice {
        params.append("notice=\(muniConversionURLQueryEncoded(notice))")
    }
    if let error {
        params.append("error=\(muniConversionURLQueryEncoded(error))")
    }

    return "/ui/muni/apps/MuniConversion/employe?\(params.joined(separator: "&"))"
}

private func normalizedMuniConversionOperation(_ rawValue: String) -> String {
    rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "convert"
        ? "convert"
        : "analyze"
}

private func normalizedMuniConversionProfileID(_ rawValue: String?) -> String {
    let allowed = Set(muniConversionProfileOptions(selectedID: "").map(\.id))
    guard let candidate = nonEmptyMuniConversionValue(rawValue), allowed.contains(candidate) else {
        return "docx_to_pdf"
    }
    return candidate
}

private func normalizedMuniConversionCollisionPolicy(_ rawValue: String?) -> String {
    switch nonEmptyMuniConversionValue(rawValue) {
    case "overwrite":
        return "overwrite"
    case "rename_with_suffix":
        return "rename_with_suffix"
    default:
        return "skip_existing"
    }
}

private func validatedMuniConversionDirectoryPath(_ rawValue: String, label: String) throws -> String {
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

private func validatedOptionalMuniConversionDestination(
    _ rawValue: String?,
    useSeparateDestination: Bool
) throws -> String? {
    guard useSeparateDestination else {
        return nil
    }
    guard let rawValue else {
        throw Abort(.badRequest, reason: "Le dossier destination est requis quand la destination distincte est activée.")
    }
    return try validatedMuniConversionDirectoryPath(rawValue, label: "destination")
}

private func loadMuniConversionResultMetadata(resultFilePath: String, logger: Logger) -> MuniConversionResultMetadata {
    guard let resultRoot = muniConversionReadJSONObject(atPath: resultFilePath, logger: logger) else {
        return .empty
    }
    let metadata = resultRoot["metadata"] as? [String: Any] ?? [:]
    return MuniConversionResultMetadata(
        sourcePath: muniConversionStringValue(from: metadata["source_path"]),
        outputRootPath: muniConversionStringValue(from: metadata["output_root_path"]),
        dryRun: muniConversionBoolValue(from: metadata["dry_run"]),
        profileID: muniConversionStringValue(from: metadata["profile_id"]),
        totalScanned: muniConversionIntValue(from: metadata["total_scanned"]),
        totalMatched: muniConversionIntValue(from: metadata["total_matched"]),
        converted: muniConversionIntValue(from: metadata["converted"]),
        simulated: muniConversionIntValue(from: metadata["simulated"]),
        ignored: muniConversionIntValue(from: metadata["ignored"]),
        skippedExisting: muniConversionIntValue(from: metadata["skipped_existing"]),
        errors: muniConversionIntValue(from: metadata["errors"])
    )
}

private func muniConversionReadJSONObject(atPath path: String, logger: Logger) -> [String: Any]? {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
    }

    do {
        let data = try Data(contentsOf: fileURL)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    } catch {
        logger.debug("Lecture JSON MuniConversion employé ignorée.", metadata: [
            "path": .string(fileURL.path),
            "error": .string(error.localizedDescription)
        ])
        return nil
    }
}

private func muniConversionSummary(
    _ rawSummary: String?,
    action: String,
    metadata: MuniConversionResultMetadata
) -> String {
    if action == "analyze" {
        return "Analyse terminée: \(muniConversionStringOrDash(metadata.totalScanned)) fichier(s) détecté(s), \(muniConversionStringOrDash(metadata.totalMatched)) correspondant(s), \(muniConversionStringOrDash(metadata.ignored)) ignoré(s)."
    }
    if metadata.dryRun == true {
        return "Simulation terminée: \(muniConversionStringOrDash(metadata.totalMatched)) fichier(s) correspondant(s), \(muniConversionStringOrDash(metadata.simulated)) conversion(s) simulée(s), \(muniConversionStringOrDash(metadata.errors)) erreur(s)."
    }
    if metadata.converted != nil || metadata.skippedExisting != nil || metadata.errors != nil {
        return "Conversion terminée: \(muniConversionStringOrDash(metadata.converted)) converti(s), \(muniConversionStringOrDash(metadata.skippedExisting)) ignoré(s) car existant(s), \(muniConversionStringOrDash(metadata.errors)) erreur(s)."
    }

    let trimmed = rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "Aucun résumé disponible." : trimmed
}

private func muniConversionStatusLabel(_ status: ToolStatus) -> String {
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

private func muniConversionStatusClass(_ status: ToolStatus) -> String {
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

private func muniConversionDiagnosticSeverityLabel(_ severity: String?) -> String {
    switch severity {
    case "blocking":
        return "Blocking"
    case "warning":
        return "Warning"
    default:
        return "Info"
    }
}

private func muniConversionDiagnosticSeverityClass(_ severity: String?) -> String {
    switch severity {
    case "blocking":
        return "diag-blocking"
    case "warning":
        return "diag-warning"
    default:
        return "diag-info"
    }
}

private func parseMuniConversionFlag(_ rawValue: String?, defaultValue: Bool = false) -> Bool {
    guard let rawValue else { return defaultValue }
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off", "":
        return false
    default:
        return defaultValue
    }
}

private func nonEmptyMuniConversionValue(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func muniConversionStringValue(from rawValue: Any?) -> String? {
    guard let rawValue = rawValue as? String else {
        return nil
    }
    return nonEmptyMuniConversionValue(rawValue)
}

private func muniConversionBoolValue(from rawValue: Any?) -> Bool? {
    if let bool = rawValue as? Bool {
        return bool
    }
    if let number = rawValue as? NSNumber {
        return number.boolValue
    }
    if let text = rawValue as? String {
        return parseMuniConversionFlag(text)
    }
    return nil
}

private func muniConversionIntValue(from rawValue: Any?) -> Int? {
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

private func muniConversionStringOrDash(_ value: Int?) -> String {
    value.map(String.init) ?? "-"
}

private func muniConversionURLQueryEncoded(_ value: String) -> String {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
