import Fluent
import Foundation
import OrchivisteKitContracts
import Vapor

private struct UIMuniRenommageEmployeeForm: Content {
    let rename_mode: String?
    let source_directory: String
    let destination_directory: String
    let source_directory_mode: String?
    let destination_directory_mode: String?
    let preset_profile: String?
    let collision_policy: String?
    let recursive: String?
    let include_hidden: String?
    let include_regex: String?
    let exclude_regex: String?
    let replace_enabled: String?
    let replace_find: String?
    let replace_with: String?
    let replace_regex: String?
    let add_prefix_enabled: String?
    let prefix: String?
    let add_suffix_enabled: String?
    let suffix: String?
    let date_prefix_enabled: String?
    let date_format: String?
    let numbering_enabled: String?
    let numbering_start: String?
    let numbering_pad: String?
    let numbering_separator: String?
    let casing_style: String?
    let parent_prefix_enabled: String?
    let strip_diacritics: String?
    let spaces_to_underscore: String?
    let regles_bundle_path: String?
    let regles_naming_rule_id: String?
    let regles_class_code: String?
    let preview_execution_id: String?
    let operation: String
}

private struct UIMuniRenommageSelectOption: Encodable {
    let id: String
    let label: String
    let selected_attr: String
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
    let manual_tab_class: String
    let auto_tab_class: String
    let source_directory: String
    let destination_directory: String
    let preset_options: [UIMuniRenommageSelectOption]
    let collision_options: [UIMuniRenommageSelectOption]
    let recursive_checked_attr: String
    let include_hidden_checked_attr: String
    let include_regex: String
    let exclude_regex: String
    let replace_enabled_checked_attr: String
    let replace_find: String
    let replace_with: String
    let replace_regex_checked_attr: String
    let add_prefix_enabled_checked_attr: String
    let prefix: String
    let add_suffix_enabled_checked_attr: String
    let suffix: String
    let date_prefix_enabled_checked_attr: String
    let date_format: String
    let numbering_enabled_checked_attr: String
    let numbering_start: String
    let numbering_pad: String
    let numbering_separator: String
    let casing_options: [UIMuniRenommageSelectOption]
    let parent_prefix_enabled_checked_attr: String
    let strip_diacritics_checked_attr: String
    let spaces_to_underscore_checked_attr: String
    let regles_bundle_path: String
    let regles_class_code: String
    let regles_source_label: String
    let regles_summary: String
    let regles_bundle_status: String
    let regles_rule_options: [UIMuniRenommageSelectOption]
    let regles_rules_present: Bool
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
    let result_regles_trace_present: Bool
    let result_regles_source: String
    let result_regles_rule_id: String
    let result_regles_bundle_version: String
    let result_regles_fallback_reason: String
    let result_regles_apply_rule_label: String
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
    let reglesSource: String?
    let reglesRuleID: String?
    let reglesBundleVersion: String?
    let reglesFallbackReason: String?
    let reglesApplyRule: Bool?
    let diagnostic: RunDiagnosticRecord?
}

private struct MuniRenommageEmployeeFormState {
    let mode: String
    let sourceDirectory: String
    let destinationDirectory: String
    let presetProfile: String
    let collisionPolicy: String
    let recursive: Bool
    let includeHidden: Bool
    let includeRegex: String
    let excludeRegex: String
    let replaceEnabled: Bool
    let replaceFind: String
    let replaceWith: String
    let replaceRegex: Bool
    let addPrefixEnabled: Bool
    let prefix: String
    let addSuffixEnabled: Bool
    let suffix: String
    let datePrefixEnabled: Bool
    let dateFormat: String
    let numberingEnabled: Bool
    let numberingStart: Int
    let numberingPad: Int
    let numberingSeparator: String
    let casingStyle: String
    let parentPrefixEnabled: Bool
    let stripDiacritics: Bool
    let spacesToUnderscore: Bool
    let reglesBundlePath: String
    let reglesNamingRuleID: String
    let reglesClassCode: String
}

func registerMuniRenommageEmployeeUIRoutes(_ app: Application) {
    let buildContext: @Sendable (Request) async throws -> UIMuniRenommageEmployeeContext = { req in
        let state = muniRenommageFormState(from: req)
        let requestedExecutionID = nonEmptyEmployeePath(req.query[String.self, at: "execution_id"])
        let requestedPreviewExecutionID = nonEmptyEmployeePath(req.query[String.self, at: "preview_execution_id"])
        let reglesSnapshot = await MuniReglesReadModelLoader.load(on: req.db, logger: req.logger)
        let reglesRules = reglesSnapshot.rules
        let effectiveReglesBundlePath = state.reglesBundlePath.isEmpty ? (reglesRules.bundlePath ?? "") : state.reglesBundlePath
        let selectedReglesRuleID = state.reglesNamingRuleID.isEmpty ? (reglesRules.namingRules.first?.id ?? "") : state.reglesNamingRuleID

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
                reglesSource: metadata.reglesSource,
                reglesRuleID: metadata.reglesRuleID,
                reglesBundleVersion: metadata.reglesBundleVersion,
                reglesFallbackReason: metadata.reglesFallbackReason,
                reglesApplyRule: metadata.reglesApplyRule,
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
                    state: state,
                    executionID: entry.executionID,
                    previewExecutionID: entry.action == "preview"
                        ? entry.executionID
                        : requestedPreviewExecutionID
                )
            ))
        }

        return UIMuniRenommageEmployeeContext(
            manual_tab_class: state.mode == "manual" ? "active" : "",
            auto_tab_class: state.mode == "auto" ? "active" : "",
            source_directory: state.sourceDirectory,
            destination_directory: state.destinationDirectory,
            preset_options: employeePresetOptions(selectedID: state.presetProfile),
            collision_options: employeeCollisionOptions(selectedID: state.collisionPolicy),
            recursive_checked_attr: state.recursive ? "checked" : "",
            include_hidden_checked_attr: state.includeHidden ? "checked" : "",
            include_regex: state.includeRegex,
            exclude_regex: state.excludeRegex,
            replace_enabled_checked_attr: state.replaceEnabled ? "checked" : "",
            replace_find: state.replaceFind,
            replace_with: state.replaceWith,
            replace_regex_checked_attr: state.replaceRegex ? "checked" : "",
            add_prefix_enabled_checked_attr: state.addPrefixEnabled ? "checked" : "",
            prefix: state.prefix,
            add_suffix_enabled_checked_attr: state.addSuffixEnabled ? "checked" : "",
            suffix: state.suffix,
            date_prefix_enabled_checked_attr: state.datePrefixEnabled ? "checked" : "",
            date_format: state.dateFormat,
            numbering_enabled_checked_attr: state.numberingEnabled ? "checked" : "",
            numbering_start: String(state.numberingStart),
            numbering_pad: String(state.numberingPad),
            numbering_separator: state.numberingSeparator,
            casing_options: employeeCasingOptions(selectedID: state.casingStyle),
            parent_prefix_enabled_checked_attr: state.parentPrefixEnabled ? "checked" : "",
            strip_diacritics_checked_attr: state.stripDiacritics ? "checked" : "",
            spaces_to_underscore_checked_attr: state.spacesToUnderscore ? "checked" : "",
            regles_bundle_path: effectiveReglesBundlePath,
            regles_class_code: state.reglesClassCode,
            regles_source_label: reglesRules.sourceLabel,
            regles_summary: reglesRules.summary,
            regles_bundle_status: effectiveReglesBundlePath.isEmpty
                ? "Aucun bundle MuniRegles disponible automatiquement."
                : effectiveReglesBundlePath,
            regles_rule_options: employeeReglesRuleOptions(
                rules: reglesRules.namingRules,
                selectedID: selectedReglesRuleID
            ),
            regles_rules_present: !reglesRules.namingRules.isEmpty,
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
            result_regles_trace_present: resultSnapshot?.reglesSource != nil ||
                resultSnapshot?.reglesRuleID != nil ||
                resultSnapshot?.reglesFallbackReason != nil,
            result_regles_source: reglesTraceSourceLabel(resultSnapshot?.reglesSource),
            result_regles_rule_id: resultSnapshot?.reglesRuleID ?? "-",
            result_regles_bundle_version: resultSnapshot?.reglesBundleVersion ?? "-",
            result_regles_fallback_reason: reglesFallbackReasonLabel(resultSnapshot?.reglesFallbackReason),
            result_regles_apply_rule_label: resultSnapshot?.reglesApplyRule == true ? "Oui" : "Non",
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
        let state = muniRenommageFormState(from: form)
        let sourceDirectory = try validatedDirectoryPath(state.sourceDirectory, label: "source")
        let destinationDirectory = try validatedDirectoryPath(state.destinationDirectory, label: "destination")
        let effectiveState = state.withValidatedPaths(sourceDirectory: sourceDirectory, destinationDirectory: destinationDirectory)
        let operation = normalizedEmployeeOperation(form.operation)

        do {
            let runtimeConfig = CockpitConfigLoader.load(logger: req.logger)
            let presetURL = try writeEmployeePresetFile(
                state: effectiveState,
                runtimeConfig: runtimeConfig
            )

            var parameters: [String: JSONValue] = [
                "preset_path": .string(presetURL.path),
                "directory_path": .string(sourceDirectory),
                "recursive": .bool(effectiveState.recursive),
                "include_hidden": .bool(effectiveState.includeHidden),
                "dry_run": .bool(operation == .preview),
                "confirm_apply": .bool(operation == .apply)
            ]
            if effectiveState.mode == "auto" {
                parameters["regles_apply_rule"] = .bool(true)
                if !effectiveState.reglesBundlePath.isEmpty {
                    parameters["regles_bundle_path"] = .string(effectiveState.reglesBundlePath)
                }
                if !effectiveState.reglesNamingRuleID.isEmpty {
                    parameters["regles_naming_rule_id"] = .string(effectiveState.reglesNamingRuleID)
                }
                if !effectiveState.reglesClassCode.isEmpty {
                    parameters["regles_class_code"] = .string(effectiveState.reglesClassCode)
                    parameters["class_code"] = .string(effectiveState.reglesClassCode)
                }
            }

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
                state: effectiveState,
                executionID: outcome.executionID,
                previewExecutionID: operation == .preview ? outcome.executionID : previewExecutionIDForRedirect,
                notice: notice
            )
            return req.redirect(to: redirect)
        } catch let abort as AbortError {
            return req.redirect(
                to: employeeMuniRenommagePageURL(
                    state: effectiveState,
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
                    state: effectiveState,
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
    let reglesSource: String?
    let reglesRuleID: String?
    let reglesBundleVersion: String?
    let reglesFallbackReason: String?
    let reglesApplyRule: Bool?

    static let empty = MuniRenommageResultMetadata(
        planDigest: nil,
        plannedItemCount: nil,
        plannedOperationCount: nil,
        warningCount: nil,
        collisionCount: nil,
        existingDestinationCount: nil,
        idempotentCount: nil,
        reglesSource: nil,
        reglesRuleID: nil,
        reglesBundleVersion: nil,
        reglesFallbackReason: nil,
        reglesApplyRule: nil
    )
}

private struct EmployeeApplyState {
    let isApplyEnabled: Bool
    let message: String?
}

private extension MuniRenommageEmployeeFormState {
    func withValidatedPaths(sourceDirectory: String, destinationDirectory: String) -> MuniRenommageEmployeeFormState {
        MuniRenommageEmployeeFormState(
            mode: mode,
            sourceDirectory: sourceDirectory,
            destinationDirectory: destinationDirectory,
            presetProfile: presetProfile,
            collisionPolicy: collisionPolicy,
            recursive: recursive,
            includeHidden: includeHidden,
            includeRegex: includeRegex,
            excludeRegex: excludeRegex,
            replaceEnabled: replaceEnabled,
            replaceFind: replaceFind,
            replaceWith: replaceWith,
            replaceRegex: replaceRegex,
            addPrefixEnabled: addPrefixEnabled,
            prefix: prefix,
            addSuffixEnabled: addSuffixEnabled,
            suffix: suffix,
            datePrefixEnabled: datePrefixEnabled,
            dateFormat: dateFormat,
            numberingEnabled: numberingEnabled,
            numberingStart: numberingStart,
            numberingPad: numberingPad,
            numberingSeparator: numberingSeparator,
            casingStyle: casingStyle,
            parentPrefixEnabled: parentPrefixEnabled,
            stripDiacritics: stripDiacritics,
            spacesToUnderscore: spacesToUnderscore,
            reglesBundlePath: reglesBundlePath,
            reglesNamingRuleID: reglesNamingRuleID,
            reglesClassCode: reglesClassCode
        )
    }
}

private func muniRenommageFormState(from req: Request) -> MuniRenommageEmployeeFormState {
    MuniRenommageEmployeeFormState(
        mode: normalizedEmployeeRenameMode(req.query[String.self, at: "rename_mode"]),
        sourceDirectory: nonEmptyEmployeePath(req.query[String.self, at: "source_directory"]) ?? "",
        destinationDirectory: nonEmptyEmployeePath(req.query[String.self, at: "destination_directory"]) ?? "",
        presetProfile: normalizedEmployeePresetProfile(req.query[String.self, at: "preset_profile"]),
        collisionPolicy: normalizedEmployeeCollisionPolicy(req.query[String.self, at: "collision_policy"]),
        recursive: parseEmployeeFlag(req.query[String.self, at: "recursive"]),
        includeHidden: parseEmployeeFlag(req.query[String.self, at: "include_hidden"]),
        includeRegex: nonEmptyEmployeePath(req.query[String.self, at: "include_regex"]) ?? "",
        excludeRegex: nonEmptyEmployeePath(req.query[String.self, at: "exclude_regex"]) ?? "",
        replaceEnabled: parseEmployeeFlag(req.query[String.self, at: "replace_enabled"]),
        replaceFind: nonEmptyEmployeePath(req.query[String.self, at: "replace_find"]) ?? "",
        replaceWith: req.query[String.self, at: "replace_with"] ?? "",
        replaceRegex: parseEmployeeFlag(req.query[String.self, at: "replace_regex"]),
        addPrefixEnabled: parseEmployeeFlag(req.query[String.self, at: "add_prefix_enabled"]),
        prefix: req.query[String.self, at: "prefix"] ?? "",
        addSuffixEnabled: parseEmployeeFlag(req.query[String.self, at: "add_suffix_enabled"]),
        suffix: req.query[String.self, at: "suffix"] ?? "",
        datePrefixEnabled: parseEmployeeFlag(req.query[String.self, at: "date_prefix_enabled"]),
        dateFormat: nonEmptyEmployeePath(req.query[String.self, at: "date_format"]) ?? "yyyy-MM-dd",
        numberingEnabled: parseEmployeeFlag(req.query[String.self, at: "numbering_enabled"]),
        numberingStart: boundedEmployeeInt(req.query[String.self, at: "numbering_start"], defaultValue: 1, range: -9999...9999),
        numberingPad: boundedEmployeeInt(req.query[String.self, at: "numbering_pad"], defaultValue: 3, range: 1...12),
        numberingSeparator: req.query[String.self, at: "numbering_separator"] ?? " - ",
        casingStyle: normalizedEmployeeCasingStyle(req.query[String.self, at: "casing_style"]),
        parentPrefixEnabled: parseEmployeeFlag(req.query[String.self, at: "parent_prefix_enabled"]),
        stripDiacritics: parseEmployeeFlag(req.query[String.self, at: "strip_diacritics"]),
        spacesToUnderscore: parseEmployeeFlag(req.query[String.self, at: "spaces_to_underscore"]),
        reglesBundlePath: nonEmptyEmployeePath(req.query[String.self, at: "regles_bundle_path"]) ?? "",
        reglesNamingRuleID: nonEmptyEmployeePath(req.query[String.self, at: "regles_naming_rule_id"]) ?? "",
        reglesClassCode: nonEmptyEmployeePath(req.query[String.self, at: "regles_class_code"]) ?? ""
    )
}

private func muniRenommageFormState(from form: UIMuniRenommageEmployeeForm) -> MuniRenommageEmployeeFormState {
    MuniRenommageEmployeeFormState(
        mode: normalizedEmployeeRenameMode(form.rename_mode),
        sourceDirectory: form.source_directory,
        destinationDirectory: form.destination_directory,
        presetProfile: normalizedEmployeePresetProfile(form.preset_profile),
        collisionPolicy: normalizedEmployeeCollisionPolicy(form.collision_policy),
        recursive: parseEmployeeFlag(form.recursive),
        includeHidden: parseEmployeeFlag(form.include_hidden),
        includeRegex: nonEmptyEmployeePath(form.include_regex) ?? "",
        excludeRegex: nonEmptyEmployeePath(form.exclude_regex) ?? "",
        replaceEnabled: parseEmployeeFlag(form.replace_enabled),
        replaceFind: nonEmptyEmployeePath(form.replace_find) ?? "",
        replaceWith: form.replace_with ?? "",
        replaceRegex: parseEmployeeFlag(form.replace_regex),
        addPrefixEnabled: parseEmployeeFlag(form.add_prefix_enabled),
        prefix: form.prefix ?? "",
        addSuffixEnabled: parseEmployeeFlag(form.add_suffix_enabled),
        suffix: form.suffix ?? "",
        datePrefixEnabled: parseEmployeeFlag(form.date_prefix_enabled),
        dateFormat: nonEmptyEmployeePath(form.date_format) ?? "yyyy-MM-dd",
        numberingEnabled: parseEmployeeFlag(form.numbering_enabled),
        numberingStart: boundedEmployeeInt(form.numbering_start, defaultValue: 1, range: -9999...9999),
        numberingPad: boundedEmployeeInt(form.numbering_pad, defaultValue: 3, range: 1...12),
        numberingSeparator: form.numbering_separator ?? " - ",
        casingStyle: normalizedEmployeeCasingStyle(form.casing_style),
        parentPrefixEnabled: parseEmployeeFlag(form.parent_prefix_enabled),
        stripDiacritics: parseEmployeeFlag(form.strip_diacritics),
        spacesToUnderscore: parseEmployeeFlag(form.spaces_to_underscore),
        reglesBundlePath: normalizedMuniEmployeePathInput(form.regles_bundle_path) ?? "",
        reglesNamingRuleID: nonEmptyEmployeePath(form.regles_naming_rule_id) ?? "",
        reglesClassCode: nonEmptyEmployeePath(form.regles_class_code) ?? ""
    )
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
    state: MuniRenommageEmployeeFormState,
    executionID: String?,
    previewExecutionID: String?,
    notice: String? = nil,
    error: String? = nil
) -> String {
    var params: [String] = []
    if state.mode != "manual" {
        params.append("rename_mode=\(employeeURLQueryEncoded(state.mode))")
    }
    if !state.sourceDirectory.isEmpty {
        params.append("source_directory=\(employeeURLQueryEncoded(state.sourceDirectory))")
    }
    if !state.destinationDirectory.isEmpty {
        params.append("destination_directory=\(employeeURLQueryEncoded(state.destinationDirectory))")
    }
    appendEmployeeQueryParam("preset_profile", state.presetProfile, defaultValue: "standard", to: &params)
    appendEmployeeQueryParam("collision_policy", state.collisionPolicy, defaultValue: "block", to: &params)
    if state.recursive {
        params.append("recursive=true")
    }
    if state.includeHidden {
        params.append("include_hidden=true")
    }
    appendEmployeeQueryParam("include_regex", state.includeRegex, to: &params)
    appendEmployeeQueryParam("exclude_regex", state.excludeRegex, to: &params)
    appendEmployeeBoolQueryParam("replace_enabled", state.replaceEnabled, to: &params)
    appendEmployeeQueryParam("replace_find", state.replaceFind, to: &params)
    appendEmployeeQueryParam("replace_with", state.replaceWith, to: &params)
    appendEmployeeBoolQueryParam("replace_regex", state.replaceRegex, to: &params)
    appendEmployeeBoolQueryParam("add_prefix_enabled", state.addPrefixEnabled, to: &params)
    appendEmployeeQueryParam("prefix", state.prefix, to: &params)
    appendEmployeeBoolQueryParam("add_suffix_enabled", state.addSuffixEnabled, to: &params)
    appendEmployeeQueryParam("suffix", state.suffix, to: &params)
    appendEmployeeBoolQueryParam("date_prefix_enabled", state.datePrefixEnabled, to: &params)
    appendEmployeeQueryParam("date_format", state.dateFormat, defaultValue: "yyyy-MM-dd", to: &params)
    appendEmployeeBoolQueryParam("numbering_enabled", state.numberingEnabled, to: &params)
    appendEmployeeQueryParam("numbering_start", String(state.numberingStart), defaultValue: "1", to: &params)
    appendEmployeeQueryParam("numbering_pad", String(state.numberingPad), defaultValue: "3", to: &params)
    appendEmployeeQueryParam("numbering_separator", state.numberingSeparator, defaultValue: " - ", to: &params)
    appendEmployeeQueryParam("casing_style", state.casingStyle, defaultValue: "unchanged", to: &params)
    appendEmployeeBoolQueryParam("parent_prefix_enabled", state.parentPrefixEnabled, to: &params)
    appendEmployeeBoolQueryParam("strip_diacritics", state.stripDiacritics, to: &params)
    appendEmployeeBoolQueryParam("spaces_to_underscore", state.spacesToUnderscore, to: &params)
    appendEmployeeQueryParam("regles_bundle_path", state.reglesBundlePath, to: &params)
    appendEmployeeQueryParam("regles_naming_rule_id", state.reglesNamingRuleID, to: &params)
    appendEmployeeQueryParam("regles_class_code", state.reglesClassCode, to: &params)
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

private func normalizedEmployeeRenameMode(_ rawValue: String?) -> String {
    nonEmptyEmployeePath(rawValue)?.lowercased() == "auto" ? "auto" : "manual"
}

private func normalizedEmployeePresetProfile(_ rawValue: String?) -> String {
    switch nonEmptyEmployeePath(rawValue)?.lowercased() {
    case "custom":
        return "custom"
    default:
        return "standard"
    }
}

private func normalizedEmployeeCollisionPolicy(_ rawValue: String?) -> String {
    switch nonEmptyEmployeePath(rawValue)?.lowercased() {
    case "block":
        return "block"
    default:
        return "block"
    }
}

private func normalizedEmployeeCasingStyle(_ rawValue: String?) -> String {
    switch nonEmptyEmployeePath(rawValue)?.lowercased() {
    case "lower":
        return "lower"
    case "upper":
        return "upper"
    case "title":
        return "title"
    default:
        return "unchanged"
    }
}

private func boundedEmployeeInt(_ rawValue: String?, defaultValue: Int, range: ClosedRange<Int>) -> Int {
    guard let rawValue,
          let parsed = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return defaultValue
    }
    return min(max(parsed, range.lowerBound), range.upperBound)
}

private func employeePresetOptions(selectedID: String) -> [UIMuniRenommageSelectOption] {
    [
        ("standard", "Profil standard Orchiviste"),
        ("custom", "Personnalisé manuel")
    ].map { id, label in
        UIMuniRenommageSelectOption(id: id, label: label, selected_attr: id == selectedID ? "selected" : "")
    }
}

private func employeeCollisionOptions(selectedID: String) -> [UIMuniRenommageSelectOption] {
    [
        ("block", "Signaler et bloquer l'application")
    ].map { id, label in
        UIMuniRenommageSelectOption(id: id, label: label, selected_attr: id == selectedID ? "selected" : "")
    }
}

private func employeeCasingOptions(selectedID: String) -> [UIMuniRenommageSelectOption] {
    [
        ("unchanged", "Conserver"),
        ("lower", "minuscules"),
        ("upper", "MAJUSCULES"),
        ("title", "Titre")
    ].map { id, label in
        UIMuniRenommageSelectOption(id: id, label: label, selected_attr: id == selectedID ? "selected" : "")
    }
}

private func employeeReglesRuleOptions(
    rules: [MuniReglesRulesNamingRuleSnapshot],
    selectedID: String
) -> [UIMuniRenommageSelectOption] {
    if rules.isEmpty {
        return [
            UIMuniRenommageSelectOption(id: "", label: "Aucune règle disponible", selected_attr: "selected")
        ]
    }
    return rules.map { rule in
        let selected = rule.id == selectedID || (selectedID.isEmpty && rule.id == rules.first?.id)
        return UIMuniRenommageSelectOption(
            id: rule.id,
            label: "\(rule.label) (\(rule.id))",
            selected_attr: selected ? "selected" : ""
        )
    }
}

private func requiredPreviewExecutionID(_ rawValue: String?) throws -> String {
    guard let executionID = nonEmptyEmployeePath(rawValue) else {
        throw Abort(.badRequest, reason: "L'application requiert une prévisualisation de référence. Lancez d'abord une prévisualisation.")
    }
    return executionID
}

private func writeEmployeePresetFile(
    state: MuniRenommageEmployeeFormState,
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

    try applyEmployeeManualRules(state, to: &rules)

    var filters = rules["filters"] as? [String: Any] ?? [:]
    filters["recursive"] = state.recursive
    filters["includeHidden"] = state.includeHidden
    filters["includeRegex"] = state.includeRegex
    filters["excludeRegex"] = state.excludeRegex
    rules["filters"] = filters

    var destination = rules["destination"] as? [String: Any] ?? [:]
    destination["enabled"] = true
    destination["url"] = URL(fileURLWithPath: state.destinationDirectory, isDirectory: true).absoluteString
    destination["copyInsteadOfMove"] = false
    rules["destination"] = destination

    preset["name"] = state.mode == "auto"
        ? "Orchiviste - Renommage automatisé IA"
        : "Orchiviste - Renommage manuel"
    preset["rules"] = rules
    root["preset"] = preset

    let presetsDirectory = URL(fileURLWithPath: runtimeConfig.runtimeDirectory, isDirectory: true)
        .appendingPathComponent("employee-presets", isDirectory: true)
    try FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)

    let sourceToken = sanitizedEmployeeFileComponent(URL(fileURLWithPath: state.sourceDirectory).lastPathComponent)
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

private func applyEmployeeManualRules(
    _ state: MuniRenommageEmployeeFormState,
    to rules: inout [String: Any]
) throws {
    if state.replaceEnabled {
        guard !state.replaceFind.isEmpty else {
            throw Abort(.badRequest, reason: "Le remplacement manuel requiert un texte ou motif à chercher.")
        }
        var replace = rules["replace"] as? [String: Any] ?? [:]
        replace["enabled"] = true
        replace["find"] = state.replaceFind
        replace["replace"] = state.replaceWith
        replace["regex"] = state.replaceRegex
        replace["caseSensitive"] = false
        rules["replace"] = replace
    }

    var add = rules["add"] as? [String: Any] ?? [:]
    add["enabled"] = state.addPrefixEnabled || state.addSuffixEnabled
    add["usePrefix"] = state.addPrefixEnabled
    add["prefix"] = state.prefix
    add["useSuffix"] = state.addSuffixEnabled
    add["suffix"] = state.suffix
    add["insertText"] = ""
    add["insertIndex"] = 1
    rules["add"] = add

    var date = rules["date"] as? [String: Any] ?? [:]
    date["enabled"] = state.datePrefixEnabled
    date["format"] = state.dateFormat.isEmpty ? "yyyy-MM-dd" : state.dateFormat
    date["usePrefix"] = state.datePrefixEnabled
    date["useSuffix"] = false
    date["useAtPosition"] = false
    date["atIndex"] = 1
    rules["date"] = date

    var numbering = rules["numbering"] as? [String: Any] ?? [:]
    numbering["enabled"] = state.numberingEnabled
    numbering["asPrefix"] = true
    numbering["start"] = state.numberingStart
    numbering["step"] = 1
    numbering["pad"] = state.numberingPad
    numbering["separator"] = state.numberingSeparator
    numbering["onlySelection"] = false
    numbering["pattern"] = ""
    rules["numbering"] = numbering

    var casing = rules["casing"] as? [String: Any] ?? [:]
    casing["enabled"] = state.casingStyle != "unchanged"
    casing["style"] = state.casingStyle
    rules["casing"] = casing

    var folder = rules["folder"] as? [String: Any] ?? [:]
    folder["enabled"] = state.parentPrefixEnabled
    folder["addParentAsPrefix"] = true
    folder["separator"] = " - "
    rules["folder"] = folder

    var special = rules["special"] as? [String: Any] ?? [:]
    special["enabled"] = true
    special["normalizeUnicode"] = true
    special["stripDiacritics"] = state.stripDiacritics
    special["dashToEnDash"] = false
    special["spacesToUnderscore"] = state.spacesToUnderscore
    rules["special"] = special
}

private func sanitizedEmployeeFileComponent(_ rawValue: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let compact = rawValue.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let rendered = String(compact).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return rendered.isEmpty ? "run" : rendered
}

private func validatedDirectoryPath(_ rawValue: String, label: String) throws -> String {
    try normalizedMuniEmployeeDirectoryPath(rawValue, label: label)
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
        idempotentCount: employeeIntValue(from: metadata["idempotent_count"]),
        reglesSource: employeeStringValue(from: metadata["regles_source"]),
        reglesRuleID: employeeStringValue(from: metadata["regles_rule_id"]),
        reglesBundleVersion: employeeStringValue(from: metadata["regles_bundle_version"]),
        reglesFallbackReason: employeeStringValue(from: metadata["regles_fallback_reason"]),
        reglesApplyRule: employeeBoolValue(from: metadata["regles_apply_rule"])
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

private func employeeBoolValue(from rawValue: Any?) -> Bool? {
    if let bool = rawValue as? Bool {
        return bool
    }
    if let number = rawValue as? NSNumber {
        return number.boolValue
    }
    if let text = rawValue as? String {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
    return nil
}

private func reglesTraceSourceLabel(_ rawValue: String?) -> String {
    switch rawValue {
    case "bundle":
        return "Bundle MuniRegles"
    case "fallback_local":
        return "Fallback local"
    case let value? where !value.isEmpty:
        return value
    default:
        return "-"
    }
}

private func reglesFallbackReasonLabel(_ rawValue: String?) -> String {
    switch rawValue {
    case "bundle_not_provided":
        return "Bundle non fourni"
    case "bundle_unreadable_or_invalid":
        return "Bundle illisible ou invalide"
    case "bundle_has_no_naming_rules":
        return "Aucune règle de nommage dans le bundle"
    case "naming_rule_id_missing":
        return "Règle de nommage non choisie"
    case "naming_rule_not_found":
        return "Règle introuvable"
    case "class_code_missing":
        return "Code de classement requis"
    case "required_metadata_fields_missing":
        return "Métadonnées requises manquantes"
    case "document_metadata_not_provided":
        return "Métadonnées document non fournies"
    case "document_metadata_unreadable_or_invalid":
        return "Métadonnées document invalides"
    case "template_not_supported":
        return "Modèle de nommage non supporté"
    case "apply_rule_disabled":
        return "Application des règles désactivée"
    case let value? where !value.isEmpty:
        return value
    default:
        return "-"
    }
}

private func parseEmployeeFlag(_ rawValue: String?, defaultValue: Bool = false) -> Bool {
    guard let rawValue else { return defaultValue }
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off":
        return false
    default:
        return defaultValue
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

private func appendEmployeeQueryParam(
    _ key: String,
    _ value: String,
    defaultValue: String = "",
    to params: inout [String]
) {
    guard value != defaultValue, !value.isEmpty else {
        return
    }
    params.append("\(key)=\(employeeURLQueryEncoded(value))")
}

private func appendEmployeeBoolQueryParam(
    _ key: String,
    _ value: Bool,
    defaultValue: Bool = false,
    to params: inout [String]
) {
    guard value != defaultValue else {
        return
    }
    params.append("\(key)=\(value ? "true" : "false")")
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
