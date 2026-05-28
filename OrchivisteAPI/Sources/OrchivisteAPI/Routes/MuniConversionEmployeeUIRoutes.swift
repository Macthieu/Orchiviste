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

private struct UIMuniConversionEmployeeResumeForm: Content {
    let execution_id: String
    let destination_directory: String?
    let use_separate_destination: String?
    let collision_policy: String?
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
    let status_class: String
    let finished_at: String
    let summary: String
    let diagnostic_label: String
    let diagnostic_present: Bool
    let diagnostic_severity_class: String
    let view_url: String
    let result_file_url: String
    let resume_present: Bool
    let resume_url: String
}

private struct UIMuniConversionResultEvent: Encodable {
    let stage_label: String
    let percent_label: String
    let message: String
    let occurred_at: String
}

private struct UIMuniConversionResultError: Encodable {
    let code: String
    let message: String
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
    let result_result_file_path: String
    let result_result_file_url: String
    let result_output_folder_url: String
    let result_output_folder_link_present: Bool
    let result_output_folder_status: String
    let result_output_file_count: String
    let result_output_file_names: [String]
    let result_output_files_present: Bool
    let result_progress_events: [UIMuniConversionResultEvent]
    let result_progress_present: Bool
    let result_error_items: [UIMuniConversionResultError]
    let result_errors_present: Bool
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
    let resume_present: Bool
    let resume_execution_id: String
    let resume_source_directory: String
    let resume_destination_directory: String
    let resume_use_separate_destination_checked_attr: String
    let resume_profile_label: String
    let resume_include_subdirectories_label: String
    let resume_mode_label: String
    let resume_collision_options: [UIMuniConversionCollisionOption]
    let resume_button_label: String
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

private struct MuniConversionResultDetails {
    let resultFilePath: String
    let resultFileURL: String
    let outputFolderURL: String?
    let outputFolderStatus: String
    let outputFileCount: String
    let outputFileNames: [String]
    let progressEvents: [UIMuniConversionResultEvent]
    let errors: [UIMuniConversionResultError]
}

private struct MuniConversionRunParameters {
    let sourceDirectory: String
    let destinationDirectory: String?
    let includeSubdirectories: Bool
    let dryRun: Bool
    let profileID: String
    let collisionPolicy: String
    let operation: String
    let rawParameters: [String: JSONValue]
}

private struct MuniConversionOutputFolderSummary {
    let url: String?
    let status: String
    let itemCount: String
    let itemNames: [String]
}

private struct MuniConversionResultSnapshot {
    let executionID: String
    let actionLabel: String
    let statusLabel: String
    let statusClass: String
    let summary: String
    let finishedAt: String
    let metadata: MuniConversionResultMetadata
    let details: MuniConversionResultDetails
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
        let requestedResumeExecutionID = nonEmptyMuniConversionValue(req.query[String.self, at: "resume_execution_id"])

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
        var selectedDiagnostic: RunDiagnosticRecord?
        if let selectedEntry {
            let diagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: selectedEntry.executionID, on: req.db)
            selectedDiagnostic = diagnostic
            let metadata = loadMuniConversionResultMetadata(resultFilePath: selectedEntry.resultFile, logger: req.logger)
            let details = loadMuniConversionResultDetails(entry: selectedEntry, metadata: metadata, logger: req.logger)
            resultSnapshot = MuniConversionResultSnapshot(
                executionID: selectedEntry.executionID,
                actionLabel: selectedEntry.action == "convert" ? "Conversion" : "Analyse",
                statusLabel: muniConversionStatusLabel(selectedEntry.status),
                statusClass: muniConversionStatusClass(selectedEntry.status),
                summary: muniConversionSummary(selectedEntry.summary, action: selectedEntry.action, metadata: metadata),
                finishedAt: selectedEntry.finishedAt,
                metadata: metadata,
                details: details,
                diagnostic: diagnostic
            )
        }

        let explicitResumeEntry = requestedResumeExecutionID.flatMap { executionID in
            recentEntries.first(where: { $0.executionID == executionID })
        }
        let resumeSourceEntry = explicitResumeEntry ?? selectedEntry
        var resumeEntry: CockpitHistoryEntry?
        var resumeParameters: MuniConversionRunParameters?
        if let candidateEntry = resumeSourceEntry {
            let candidateMetadata: MuniConversionResultMetadata
            let candidateDiagnostic: RunDiagnosticRecord?
            if candidateEntry.executionID == selectedEntry?.executionID {
                candidateMetadata = resultSnapshot?.metadata
                    ?? loadMuniConversionResultMetadata(resultFilePath: candidateEntry.resultFile, logger: req.logger)
                candidateDiagnostic = selectedDiagnostic
            } else {
                candidateMetadata = loadMuniConversionResultMetadata(resultFilePath: candidateEntry.resultFile, logger: req.logger)
                candidateDiagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: candidateEntry.executionID, on: req.db)
            }
            let candidateParameters = loadMuniConversionRunParameters(entry: candidateEntry, logger: req.logger)
            if isMuniConversionResumeCandidate(
                entry: candidateEntry,
                metadata: candidateMetadata,
                diagnostic: candidateDiagnostic,
                parameters: candidateParameters
            ) {
                resumeEntry = candidateEntry
                resumeParameters = candidateParameters
            }
        }

        var recentRuns: [UIMuniConversionEmployeeRecentRun] = []
        recentRuns.reserveCapacity(min(recentEntries.count, 6))
        for entry in recentEntries.prefix(6) {
            let diagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: entry.executionID, on: req.db)
            let metadata = loadMuniConversionResultMetadata(resultFilePath: entry.resultFile, logger: req.logger)
            let runParameters = loadMuniConversionRunParameters(entry: entry, logger: req.logger)
            let resumePresent = isMuniConversionResumeCandidate(
                entry: entry,
                metadata: metadata,
                diagnostic: diagnostic,
                parameters: runParameters
            )
            recentRuns.append(UIMuniConversionEmployeeRecentRun(
                execution_id: entry.executionID,
                action_label: entry.action == "convert" ? "Conversion" : "Analyse",
                status_label: muniConversionStatusLabel(entry.status),
                status_class: muniConversionStatusClass(entry.status),
                finished_at: entry.finishedAt,
                summary: muniConversionSummary(entry.summary, action: entry.action, metadata: metadata),
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
                ),
                result_file_url: employeeMuniConversionResultFileURL(executionID: entry.executionID),
                resume_present: resumePresent,
                resume_url: resumePresent ? employeeMuniConversionPageURL(
                    sourceDirectory: sourceDirectory,
                    destinationDirectory: destinationDirectory,
                    useSeparateDestination: useSeparateDestination,
                    includeSubdirectories: includeSubdirectories,
                    dryRun: dryRun,
                    profileID: selectedProfileID,
                    collisionPolicy: selectedCollisionPolicy,
                    executionID: entry.executionID,
                    resumeExecutionID: entry.executionID
                ) : ""
            ))
        }

        let resumeCollisionPolicy = resumeParameters?.collisionPolicy ?? selectedCollisionPolicy
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
            result_result_file_path: resultSnapshot?.details.resultFilePath ?? "-",
            result_result_file_url: resultSnapshot?.details.resultFileURL ?? "",
            result_output_folder_url: resultSnapshot?.details.outputFolderURL ?? "",
            result_output_folder_link_present: resultSnapshot?.details.outputFolderURL != nil,
            result_output_folder_status: resultSnapshot?.details.outputFolderStatus ?? "Aucun dossier de sortie disponible.",
            result_output_file_count: resultSnapshot?.details.outputFileCount ?? "-",
            result_output_file_names: resultSnapshot?.details.outputFileNames ?? [],
            result_output_files_present: !(resultSnapshot?.details.outputFileNames ?? []).isEmpty,
            result_progress_events: resultSnapshot?.details.progressEvents ?? [],
            result_progress_present: !(resultSnapshot?.details.progressEvents ?? []).isEmpty,
            result_error_items: resultSnapshot?.details.errors ?? [],
            result_errors_present: !(resultSnapshot?.details.errors ?? []).isEmpty,
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
            resume_present: resumeParameters != nil,
            resume_execution_id: resumeEntry?.executionID ?? "",
            resume_source_directory: resumeParameters?.sourceDirectory ?? "",
            resume_destination_directory: resumeParameters?.destinationDirectory ?? "",
            resume_use_separate_destination_checked_attr: resumeParameters?.destinationDirectory != nil ? "checked" : "",
            resume_profile_label: resumeParameters.map { muniConversionProfileLabel($0.profileID) } ?? "",
            resume_include_subdirectories_label: resumeParameters?.includeSubdirectories == true ? "Oui" : "Non",
            resume_mode_label: resumeParameters.map(muniConversionResumeModeLabel) ?? "",
            resume_collision_options: muniConversionCollisionOptions(selectedID: resumeCollisionPolicy),
            resume_button_label: resumeParameters.map(muniConversionResumeButtonLabel) ?? "Relancer",
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

    app.get("ui", "muni", "apps", "MuniConversion", "employe", "result", ":executionID") { req async throws -> Response in
        guard let executionID = nonEmptyMuniConversionValue(req.parameters.get("executionID")) else {
            throw Abort(.badRequest, reason: "Identifiant d'exécution manquant.")
        }
        let entry = try await fetchMuniConversionRun(executionID: executionID, on: req.db)
        let resultURL = URL(fileURLWithPath: entry.resultFile)
        guard FileManager.default.fileExists(atPath: resultURL.path) else {
            throw Abort(.notFound, reason: "Le fichier résultat est indisponible.")
        }

        let response = try await req.fileio.asyncStreamFile(at: resultURL.path)
        response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
        response.headers.replaceOrAdd(
            name: .contentDisposition,
            value: "inline; filename=\"\(resultURL.lastPathComponent)\""
        )
        return response
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

    app.on(.POST, "ui", "muni", "apps", "MuniConversion", "employe", "resume", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        let form = try req.content.decode(UIMuniConversionEmployeeResumeForm.self)
        let collisionPolicy = normalizedMuniConversionCollisionPolicy(form.collision_policy)
        let useSeparateDestination = parseMuniConversionFlag(form.use_separate_destination)
            || nonEmptyMuniConversionValue(form.destination_directory) != nil

        var redirectSourceDirectory = ""
        var redirectDestinationDirectory = form.destination_directory ?? ""
        var redirectIncludeSubdirectories = false
        var redirectDryRun = true
        var redirectProfileID = "docx_to_pdf"

        do {
            let previousEntry = try await fetchMuniConversionRun(executionID: form.execution_id, on: req.db)
            guard let previousRun = loadMuniConversionRunParameters(entry: previousEntry, logger: req.logger),
                  previousRun.operation == "convert" else {
                throw Abort(.badRequest, reason: "Ce run ne contient pas les paramètres nécessaires à une reprise employé.")
            }

            let sourceDirectory = try validatedMuniConversionDirectoryPath(previousRun.sourceDirectory, label: "source")
            let destinationDirectory = try validatedOptionalMuniConversionDestination(
                form.destination_directory,
                useSeparateDestination: useSeparateDestination
            )

            redirectSourceDirectory = sourceDirectory
            redirectDestinationDirectory = destinationDirectory ?? ""
            redirectIncludeSubdirectories = previousRun.includeSubdirectories
            redirectDryRun = previousRun.dryRun
            redirectProfileID = previousRun.profileID

            let confirmConvert = previousRun.operation == "convert" && !previousRun.dryRun
            var parameters = previousRun.rawParameters
            parameters["source_path"] = .string(sourceDirectory)
            parameters["profile_id"] = .string(previousRun.profileID)
            parameters["include_subdirectories"] = .bool(previousRun.includeSubdirectories)
            parameters["collision_policy"] = .string(collisionPolicy)
            parameters["dry_run"] = .bool(previousRun.dryRun)
            parameters["confirm_convert"] = .bool(confirmConvert)
            if let destinationDirectory {
                parameters["output_path"] = .string(destinationDirectory)
            } else {
                parameters.removeValue(forKey: "output_path")
            }

            let launchRequest = CockpitLaunchRequest(
                toolID: "MuniConversion",
                action: previousRun.operation,
                correlationID: req.headers.first(name: "x-correlation-id"),
                workspacePath: nil,
                inputArtifacts: [],
                parameters: parameters,
                allowDestructive: confirmConvert
            )

            let outcome = try await CockpitCanonicalLauncher.launch(launchRequest, on: req.db, logger: req.logger)
            let notice = previousRun.dryRun
                ? "Reprise en simulation \(outcome.executionID) terminée."
                : "Reprise de conversion \(outcome.executionID) terminée."

            return req.redirect(to: employeeMuniConversionPageURL(
                sourceDirectory: sourceDirectory,
                destinationDirectory: destinationDirectory ?? "",
                useSeparateDestination: destinationDirectory != nil,
                includeSubdirectories: previousRun.includeSubdirectories,
                dryRun: previousRun.dryRun,
                profileID: previousRun.profileID,
                collisionPolicy: collisionPolicy,
                executionID: outcome.executionID,
                notice: notice
            ))
        } catch let abort as AbortError {
            return req.redirect(to: employeeMuniConversionPageURL(
                sourceDirectory: redirectSourceDirectory,
                destinationDirectory: redirectDestinationDirectory,
                useSeparateDestination: useSeparateDestination,
                includeSubdirectories: redirectIncludeSubdirectories,
                dryRun: redirectDryRun,
                profileID: redirectProfileID,
                collisionPolicy: collisionPolicy,
                executionID: form.execution_id,
                resumeExecutionID: form.execution_id,
                error: abort.reason.isEmpty ? "Échec reprise MuniConversion." : abort.reason
            ))
        } catch {
            req.logger.error("Échec reprise employé MuniConversion.", metadata: [
                "execution_id": .string(form.execution_id),
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: employeeMuniConversionPageURL(
                sourceDirectory: redirectSourceDirectory,
                destinationDirectory: redirectDestinationDirectory,
                useSeparateDestination: useSeparateDestination,
                includeSubdirectories: redirectIncludeSubdirectories,
                dryRun: redirectDryRun,
                profileID: redirectProfileID,
                collisionPolicy: collisionPolicy,
                executionID: form.execution_id,
                resumeExecutionID: form.execution_id,
                error: "Erreur interne pendant la reprise de MuniConversion."
            ))
        }
    }
}

private func muniConversionProfileOptions(selectedID: String) -> [UIMuniConversionProfileOption] {
    [
        ("doc_to_docx", "DOC -> DOCX"),
        ("doc_to_pdf", "DOC -> PDF"),
        ("docx_to_pdf", "DOCX -> PDF"),
        ("docx_to_doc", "DOCX -> DOC"),
        ("xls_to_xlsx", "XLS -> XLSX"),
        ("xls_to_pdf", "XLS -> PDF"),
        ("xlsx_to_pdf", "XLSX -> PDF"),
        ("xlsx_to_xls", "XLSX -> XLS"),
        ("ppt_to_pptx", "PPT -> PPTX"),
        ("ppt_to_pdf", "PPT -> PDF"),
        ("pptx_to_pdf", "PPTX -> PDF"),
        ("pptx_to_ppt", "PPTX -> PPT"),
        ("rtf_to_docx", "RTF -> DOCX"),
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

private func muniConversionProfileLabel(_ profileID: String) -> String {
    muniConversionProfileOptions(selectedID: profileID)
        .first(where: { $0.id == profileID })?
        .label ?? profileID
}

private func muniConversionResumeModeLabel(_ parameters: MuniConversionRunParameters) -> String {
    if parameters.dryRun {
        return "Simulation de conversion"
    }
    return "Conversion réelle"
}

private func muniConversionResumeButtonLabel(_ parameters: MuniConversionRunParameters) -> String {
    if parameters.dryRun {
        return "Relancer la simulation"
    }
    return "Relancer la conversion"
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
    resumeExecutionID: String? = nil,
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
    if let resumeExecutionID {
        params.append("resume_execution_id=\(muniConversionURLQueryEncoded(resumeExecutionID))")
    }
    if let notice {
        params.append("notice=\(muniConversionURLQueryEncoded(notice))")
    }
    if let error {
        params.append("error=\(muniConversionURLQueryEncoded(error))")
    }

    return "/ui/muni/apps/MuniConversion/employe?\(params.joined(separator: "&"))"
}

private func employeeMuniConversionResultFileURL(executionID: String) -> String {
    "/ui/muni/apps/MuniConversion/employe/result/\(muniConversionURLPathEncoded(executionID))"
}

private func fetchMuniConversionRun(executionID: String, on db: Database) async throws -> CockpitHistoryEntry {
    let entries = try await CockpitRegistryRepository.listRecentRuns(appID: "MuniConversion", limit: 50, on: db)
    guard let entry = entries.first(where: { $0.executionID == executionID }) else {
        throw Abort(.notFound, reason: "Run MuniConversion introuvable.")
    }
    return entry
}

private func loadMuniConversionRunParameters(
    entry: CockpitHistoryEntry,
    logger: Logger
) -> MuniConversionRunParameters? {
    let requestURL = URL(fileURLWithPath: entry.requestFile)
    guard FileManager.default.fileExists(atPath: requestURL.path) else {
        return nil
    }

    do {
        let data = try Data(contentsOf: requestURL)
        let request = try JSONDecoder().decode(ToolRequest.self, from: data)
        guard request.tool == "MuniConversion",
              let sourceDirectory = muniConversionStringParameter("source_path", from: request.parameters) else {
            return nil
        }

        let profileID = normalizedMuniConversionProfileID(
            muniConversionStringParameter("profile_id", from: request.parameters)
        )
        let collisionPolicy = normalizedMuniConversionCollisionPolicy(
            muniConversionStringParameter("collision_policy", from: request.parameters)
        )
        let includeSubdirectories = muniConversionBoolParameter("include_subdirectories", from: request.parameters) ?? false
        let dryRun = muniConversionBoolParameter("dry_run", from: request.parameters) ?? entry.dryRun ?? true

        return MuniConversionRunParameters(
            sourceDirectory: sourceDirectory,
            destinationDirectory: muniConversionStringParameter("output_path", from: request.parameters),
            includeSubdirectories: includeSubdirectories,
            dryRun: dryRun,
            profileID: profileID,
            collisionPolicy: collisionPolicy,
            operation: normalizedMuniConversionOperation(request.action),
            rawParameters: request.parameters
        )
    } catch {
        logger.debug("Lecture request.json MuniConversion ignorée pour reprise employé.", metadata: [
            "path": .string(requestURL.path),
            "error": .string(error.localizedDescription)
        ])
        return nil
    }
}

private func isMuniConversionResumeCandidate(
    entry: CockpitHistoryEntry,
    metadata: MuniConversionResultMetadata,
    diagnostic: RunDiagnosticRecord?,
    parameters: MuniConversionRunParameters?
) -> Bool {
    guard let parameters, parameters.operation == "convert" else {
        return false
    }
    if entry.status == .failed || entry.status == .needsReview {
        return true
    }
    if (metadata.errors ?? 0) > 0 || (metadata.skippedExisting ?? 0) > 0 {
        return true
    }
    if diagnostic != nil {
        return true
    }

    let summary = (entry.summary ?? "").lowercased()
    return summary.contains("collision") ||
        summary.contains("destination") ||
        summary.contains("existant") ||
        summary.contains("existing")
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
    try normalizedMuniEmployeeDirectoryPath(rawValue, label: label)
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

private func loadMuniConversionResultDetails(
    entry: CockpitHistoryEntry,
    metadata: MuniConversionResultMetadata,
    logger: Logger
) -> MuniConversionResultDetails {
    let resultFileURL = URL(fileURLWithPath: entry.resultFile)
    var progressEvents: [UIMuniConversionResultEvent] = []
    var errors: [UIMuniConversionResultError] = []
    var artifactOutputPath: String?

    if let data = try? Data(contentsOf: resultFileURL),
       let result = try? JSONDecoder().decode(ToolResult.self, from: data) {
        progressEvents = result.progressEvents.suffix(4).map { event in
            UIMuniConversionResultEvent(
                stage_label: muniConversionProgressStageLabel(event.stage),
                percent_label: event.percent.map { "\($0) %" } ?? "-",
                message: nonEmptyMuniConversionValue(event.message) ?? "Étape enregistrée.",
                occurred_at: event.occurredAt
            )
        }
        errors = result.errors.prefix(5).map { error in
            UIMuniConversionResultError(code: error.code, message: error.message)
        }
        artifactOutputPath = result.outputArtifacts
            .first(where: { $0.id == "output_root" })
            .flatMap { muniConversionLocalPath(fromURI: $0.uri) }
    } else {
        logger.debug("Détails result.json MuniConversion non décodés pour affichage employé.", metadata: [
            "path": .string(resultFileURL.path)
        ])
    }

    let outputSummary = muniConversionOutputFolderSummary(path: metadata.outputRootPath ?? artifactOutputPath)
    return MuniConversionResultDetails(
        resultFilePath: resultFileURL.path,
        resultFileURL: employeeMuniConversionResultFileURL(executionID: entry.executionID),
        outputFolderURL: outputSummary.url,
        outputFolderStatus: outputSummary.status,
        outputFileCount: outputSummary.itemCount,
        outputFileNames: outputSummary.itemNames,
        progressEvents: progressEvents,
        errors: errors
    )
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

private func muniConversionOutputFolderSummary(path rawPath: String?) -> MuniConversionOutputFolderSummary {
    guard let rawPath = nonEmptyMuniConversionValue(rawPath), rawPath != "-" else {
        return MuniConversionOutputFolderSummary(
            url: nil,
            status: "Aucun dossier de sortie déclaré.",
            itemCount: "-",
            itemNames: []
        )
    }

    let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return MuniConversionOutputFolderSummary(
            url: "/ui/fs/list?path=\(muniConversionURLQueryEncoded(url.path))",
            status: "Dossier de sortie introuvable ou inaccessible: \(url.path)",
            itemCount: "-",
            itemNames: []
        )
    }

    do {
        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let sortedItems = items.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
        let previewNames = sortedItems.prefix(6).map { item -> String in
            let isChildDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isChildDirectory ? "\(item.lastPathComponent)/" : item.lastPathComponent
        }
        return MuniConversionOutputFolderSummary(
            url: "/ui/fs/list?path=\(muniConversionURLQueryEncoded(url.path))",
            status: "Dossier de sortie accessible: \(url.path)",
            itemCount: "\(items.count) élément(s) visible(s)",
            itemNames: previewNames
        )
    } catch {
        return MuniConversionOutputFolderSummary(
            url: "/ui/fs/list?path=\(muniConversionURLQueryEncoded(url.path))",
            status: "Dossier de sortie trouvé, mais liste indisponible: \(error.localizedDescription)",
            itemCount: "-",
            itemNames: []
        )
    }
}

private func muniConversionLocalPath(fromURI rawURI: String) -> String? {
    if rawURI.hasPrefix("file://") {
        return URL(string: rawURI)?.path
    }
    return nonEmptyMuniConversionValue(rawURI)
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

private func muniConversionProgressStageLabel(_ stage: String) -> String {
    switch stage {
    case "accepted":
        return "Demande reçue"
    case "processing":
        return "Traitement"
    case "completed":
        return "Terminé"
    default:
        return stage
    }
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

private func muniConversionStringParameter(_ key: String, from parameters: [String: JSONValue]) -> String? {
    guard let value = parameters[key] else {
        return nil
    }
    if case .string(let text) = value {
        return nonEmptyMuniConversionValue(text)
    }
    return nil
}

private func muniConversionBoolParameter(_ key: String, from parameters: [String: JSONValue]) -> Bool? {
    guard let value = parameters[key] else {
        return nil
    }
    switch value {
    case .bool(let flag):
        return flag
    case .string(let text):
        return parseMuniConversionFlag(text)
    case .number(let number):
        return number != 0
    default:
        return nil
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

private func muniConversionURLPathEncoded(_ value: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
