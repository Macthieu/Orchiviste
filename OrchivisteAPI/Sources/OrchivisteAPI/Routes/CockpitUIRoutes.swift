import Fluent
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
    let detail_url: String
}

private struct UIMuniStoreAction: Encodable {
    let action_key: String
    let action_label: String
    let action_url: String
    let is_disabled: Bool
    let is_primary: Bool
    let action_class: String
    let disabled_reason: String
}

private struct UIMuniStoreModule: Encodable {
    let app_id: String
    let display_name: String
    let description: String
    let version: String
    let installed_label: String
    let visible_state: String
    let visible_state_class: String
    let employee_readiness_label: String
    let employee_readiness_class: String
    let employee_readiness_reason: String
    let integration_status: String
    let availability_reason: String
    let actions: [UIMuniStoreAction]
    let actions_present: Bool
}

private struct UIMuniStoreContext: Encodable {
    let modules: [UIMuniStoreModule]
    let modules_present: Bool
    let notice: String?
    let error: String?
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
    let priority_diagnostic_present: Bool
    let priority_diagnostic_id: String
    let priority_diagnostic_label: String
    let priority_diagnostic_severity: String
    let priority_diagnostic_severity_label: String
    let priority_diagnostic_cta: String
    let priority_diagnostic_cta_present: Bool
    let priority_diagnostic_blocking: Bool
}

private struct UICockpitPriorityRunRow: Encodable {
    let execution_id: String
    let tool_id: String
    let action: String
    let status_label: String
    let priority_diagnostic_id: String
    let priority_diagnostic_label: String
    let priority_diagnostic_severity: String
    let priority_diagnostic_severity_label: String
    let priority_diagnostic_cta: String
    let priority_diagnostic_cta_present: Bool
    let priority_diagnostic_blocking: Bool
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
    let selected_action_apply_blocked: Bool
    let selected_action_apply_blocked_attr: String
    let apply_blocking_guard_available: Bool
    let apply_blocking_guard_reason: String
    let apply_blocking_guard_reason_present: Bool
    let history_rows: [UICockpitHistoryRow]
    let history_present: Bool
    let history_file: String
    let priority_rows: [UICockpitPriorityRunRow]
    let priority_present: Bool
    let notice: String?
    let error: String?
}

private struct UIMuniAppActionSummary: Encodable {
    let action_key: String
    let action_label: String
    let is_primary: Bool
    let launch_url: String
}

private struct UIMuniRunProfileSummary: Encodable {
    let profile_key: String
    let display_name: String
    let action_key: String
    let parameters_json: String
    let allow_destructive: Bool
    let expert_only: Bool
    let launch_url: String
}

private struct UIMuniAppRunSummary: Encodable {
    let execution_id: String
    let action: String
    let status: String
    let status_label: String
    let finished_at: String
    let summary: String
    let diagnostic_present: Bool
    let diagnostic_label: String
    let diagnostic_severity: String
    let diagnostic_severity_label: String
    let diagnostic_cta: String
    let diagnostic_cta_present: Bool
}

private struct UIMuniAppContext: Encodable {
    let app_id: String
    let display_name: String
    let mission: String
    let version: String
    let integration_status: String
    let capabilities: String
    let repository_path: String
    let executable: String
    let default_action: String
    let availability_label: String
    let availability_reason: String
    let actions: [UIMuniAppActionSummary]
    let actions_present: Bool
    let profiles: [UIMuniRunProfileSummary]
    let profiles_present: Bool
    let recent_runs: [UIMuniAppRunSummary]
    let recent_runs_present: Bool
    let expert_launch_url: String
    let back_to_catalog_url: String
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
    var collisionCount: Int?
    var idempotentCount: Int?
    var planDigest: String?
    var errors: [String]
    var warnings: [String]

    static let empty = UICockpitHistoryDiagnostics(
        extractionProvenance: nil,
        reglesSource: nil,
        reglesBundleVersion: nil,
        reglesModuleVersion: nil,
        reglesRuleID: nil,
        reglesFallbackReason: nil,
        collisionCount: nil,
        idempotentCount: nil,
        planDigest: nil,
        errors: [],
        warnings: []
    )

    var hasDiagnostics: Bool {
        extractionProvenance != nil ||
        reglesSource != nil ||
        reglesBundleVersion != nil ||
        reglesModuleVersion != nil ||
        reglesRuleID != nil ||
        reglesFallbackReason != nil ||
        collisionCount != nil ||
        idempotentCount != nil ||
        planDigest != nil ||
        !errors.isEmpty ||
        !warnings.isEmpty
    }
}

private struct UICockpitPriorityDiagnosticSummary: Sendable {
    let id: String
    let label: String
    let severity: String
    let severityLabel: String
    let cta: String?

    var isBlocking: Bool {
        severity == "blocking"
    }
}

func registerCockpitUIRoutes(_ app: Application) {
    let buildMuniStoreContext: @Sendable (Request) async throws -> UIMuniStoreContext = { req in
        let baseConfig = CockpitConfigLoader.load(logger: req.logger)
        let appRecords = try await CockpitRegistryRepository.listMuniApps(
            baseConfig: baseConfig,
            on: req.db
        )
        let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)

        let modules = appRecords.map { appRecord in
            let descriptor = appRecord.descriptor
            let runtimeTool = runtime.tools.first(where: { $0.descriptor.id == descriptor.id })
            let state = muniStoreVisibleState(for: descriptor, runtimeTool: runtimeTool)
            let employeeReadiness = muniStoreEmployeeReadiness(for: descriptor.id)
            let actions = muniStoreActions(for: descriptor.id)

            return UIMuniStoreModule(
                app_id: descriptor.id,
                display_name: descriptor.displayName,
                description: descriptor.mission,
                version: descriptor.version,
                installed_label: "installe",
                visible_state: state.label,
                visible_state_class: state.cssClass,
                employee_readiness_label: employeeReadiness.label,
                employee_readiness_class: employeeReadiness.cssClass,
                employee_readiness_reason: employeeReadiness.reason,
                integration_status: descriptor.integrationStatus,
                availability_reason: runtimeTool?.availabilityReason ?? "Disponibilité non déterminée.",
                actions: actions,
                actions_present: !actions.isEmpty
            )
        }

        return UIMuniStoreContext(
            modules: modules,
            modules_present: !modules.isEmpty,
            notice: nonEmpty(req.query[String.self, at: "notice"]),
            error: nonEmpty(req.query[String.self, at: "error"])
        )
    }

    let buildPilotageContext: @Sendable (Request) async -> UICockpitContext = { req in
        let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
        let selectedToolID = nonEmpty(req.query[String.self, at: "tool"]) ?? runtime.tools.first?.descriptor.id ?? ""
        let selectedTool = runtime.tools.first(where: { $0.descriptor.id == selectedToolID }) ?? runtime.tools.first

        let selectedAction = nonEmpty(req.query[String.self, at: "action"]) ?? selectedTool?.descriptor.defaultAction ?? "run"
        let selectedWorkspacePath = nonEmpty(req.query[String.self, at: "workspace_path"]) ?? runtime.config.workspacePath
        let selectedParametersJSON = nonEmpty(req.query[String.self, at: "parameters_json"]) ?? prettyJSONString(selectedTool?.descriptor.defaultParameters ?? [:])
        let selectedInputArtifactsJSON = nonEmpty(req.query[String.self, at: "input_artifacts_json"]) ?? "[]"
        let selectedAllowDestructive = parseBooleanFlag(req.query[String.self, at: "allow_destructive"], defaultValue: false)

        let history = await CockpitCanonicalLauncher.history(limit: 25, on: req.db, logger: req.logger)

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
                repository_path: tool.descriptor.repositoryPath ?? "-",
                detail_url: employeeDetailURL(for: tool.descriptor.id)
            )
        }

        let historyRows = history.entries.map { entry in
            let diagnostics = loadHistoryDiagnostics(for: entry, logger: req.logger)
            let warningSummary = summarizeWarnings(diagnostics.warnings)
            let priorityDiagnostic = prioritizedDiagnostic(for: entry, diagnostics: diagnostics)
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
                warnings_present: !diagnostics.warnings.isEmpty,
                priority_diagnostic_present: priorityDiagnostic != nil,
                priority_diagnostic_id: priorityDiagnostic?.id ?? "-",
                priority_diagnostic_label: priorityDiagnostic?.label ?? "-",
                priority_diagnostic_severity: priorityDiagnostic?.severity ?? "info",
                priority_diagnostic_severity_label: priorityDiagnostic?.severityLabel ?? "Info",
                priority_diagnostic_cta: priorityDiagnostic?.cta ?? "-",
                priority_diagnostic_cta_present: priorityDiagnostic?.cta != nil,
                priority_diagnostic_blocking: priorityDiagnostic?.isBlocking ?? false
            )
        }

        let priorityRows = historyRows
            .filter(\.priority_diagnostic_present)
            .prefix(5)
            .map { row in
                UICockpitPriorityRunRow(
                    execution_id: row.execution_id,
                    tool_id: row.tool_id,
                    action: row.action,
                    status_label: row.status_label,
                    priority_diagnostic_id: row.priority_diagnostic_id,
                    priority_diagnostic_label: row.priority_diagnostic_label,
                    priority_diagnostic_severity: row.priority_diagnostic_severity,
                    priority_diagnostic_severity_label: row.priority_diagnostic_severity_label,
                    priority_diagnostic_cta: row.priority_diagnostic_cta,
                    priority_diagnostic_cta_present: row.priority_diagnostic_cta_present,
                    priority_diagnostic_blocking: row.priority_diagnostic_blocking
                )
            }

        let applyBlockingGuardReason = latestBlockingGuardReason(in: history.entries, logger: req.logger)
        let applyBlockingGuardAvailable = applyBlockingGuardReason != nil
        let selectedActionApplyBlocked = selectedAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "apply" && applyBlockingGuardAvailable

        return UICockpitContext(
            tools: toolCards,
            tools_present: !toolCards.isEmpty,
            selected_tool_id: selectedToolID,
            selected_action: selectedAction,
            selected_workspace_path: selectedWorkspacePath,
            selected_parameters_json: selectedParametersJSON,
            selected_input_artifacts_json: selectedInputArtifactsJSON,
            selected_allow_destructive_attr: selectedAllowDestructive ? "checked" : "",
            selected_action_apply_blocked: selectedActionApplyBlocked,
            selected_action_apply_blocked_attr: selectedActionApplyBlocked ? "disabled" : "",
            apply_blocking_guard_available: applyBlockingGuardAvailable,
            apply_blocking_guard_reason: applyBlockingGuardReason ?? "",
            apply_blocking_guard_reason_present: applyBlockingGuardAvailable,
            history_rows: historyRows,
            history_present: !historyRows.isEmpty,
            history_file: history.historyFile,
            priority_rows: priorityRows,
            priority_present: !priorityRows.isEmpty,
            notice: nonEmpty(req.query[String.self, at: "notice"]),
            error: nonEmpty(req.query[String.self, at: "error"])
        )
    }

    let buildMuniAppContext: @Sendable (Request) async throws -> UIMuniAppContext = { req in
        let explicitAppID = explicitMuniAppID(for: req.url.path)
        guard let appID = nonEmpty(req.parameters.get("id")) ?? explicitAppID else {
            throw Abort(.badRequest, reason: "Identifiant application Muni manquant.")
        }

        let baseConfig = CockpitConfigLoader.load(logger: req.logger)
        guard let appRecord = try await CockpitRegistryRepository.fetchMuniApp(
            appID: appID,
            baseConfig: baseConfig,
            on: req.db
        ) else {
            throw Abort(.notFound, reason: "Application Muni introuvable: \(appID)")
        }

        let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
        let runtimeTool = runtime.tools.first(where: { $0.descriptor.id == appID })
        let recentEntries = try await CockpitRegistryRepository.listRecentRuns(appID: appID, limit: 6, on: req.db)

        var recentRuns: [UIMuniAppRunSummary] = []
        recentRuns.reserveCapacity(recentEntries.count)
        for entry in recentEntries {
            let diagnostic = try await CockpitRegistryRepository.topDiagnostic(executionID: entry.executionID, on: req.db)
            recentRuns.append(
                UIMuniAppRunSummary(
                    execution_id: entry.executionID,
                    action: entry.action,
                    status: entry.status.rawValue,
                    status_label: uiStatusLabel(entry.status),
                    finished_at: entry.finishedAt,
                    summary: entry.summary ?? "-",
                    diagnostic_present: diagnostic != nil,
                    diagnostic_label: diagnostic?.label ?? "-",
                    diagnostic_severity: diagnostic?.severity ?? "info",
                    diagnostic_severity_label: uiDiagnosticSeverityLabel(diagnostic?.severity),
                    diagnostic_cta: diagnostic?.cta ?? "-",
                    diagnostic_cta_present: diagnostic?.cta != nil
                )
            )
        }

        let actions = appRecord.actions.map { action in
            UIMuniAppActionSummary(
                action_key: action.actionKey,
                action_label: action.actionLabel,
                is_primary: action.isPrimary,
                launch_url: "/ui/pilotage/lancer?tool=\(urlQueryEncoded(appID))&action=\(urlQueryEncoded(action.actionKey))"
            )
        }
        let profiles = appRecord.profiles.map { profile in
            UIMuniRunProfileSummary(
                profile_key: profile.profileKey,
                display_name: profile.displayName,
                action_key: profile.actionKey,
                parameters_json: prettyJSONString(profile.parameters),
                allow_destructive: profile.allowDestructive,
                expert_only: profile.expertOnly,
                launch_url: "/ui/pilotage/lancer?tool=\(urlQueryEncoded(appID))&action=\(urlQueryEncoded(profile.actionKey))&parameters_json=\(urlQueryEncoded(prettyJSONString(profile.parameters)))&allow_destructive=\(profile.allowDestructive ? "true" : "false")"
            )
        }

        return UIMuniAppContext(
            app_id: appRecord.descriptor.id,
            display_name: appRecord.descriptor.displayName,
            mission: appRecord.descriptor.mission,
            version: appRecord.descriptor.version,
            integration_status: appRecord.descriptor.integrationStatus,
            capabilities: appRecord.descriptor.capabilities.joined(separator: ", "),
            repository_path: appRecord.descriptor.repositoryPath ?? "-",
            executable: runtimeTool?.resolvedExecutable ?? appRecord.descriptor.executablePath ?? appRecord.descriptor.executable,
            default_action: appRecord.descriptor.defaultAction,
            availability_label: runtimeTool?.isAvailable == true ? "Prêt" : "Non prêt",
            availability_reason: runtimeTool?.availabilityReason ?? "Disponibilité non déterminée.",
            actions: actions,
            actions_present: !actions.isEmpty,
            profiles: profiles,
            profiles_present: !profiles.isEmpty,
            recent_runs: recentRuns,
            recent_runs_present: !recentRuns.isEmpty,
            expert_launch_url: "/ui/pilotage/lancer?tool=\(urlQueryEncoded(appID))",
            back_to_catalog_url: "/ui/pilotage/catalogue",
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

            let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
            let selectedTool = runtime.tools.first(where: { $0.descriptor.id == toolID }) ?? runtime.tools.first
            let selectedAction = normalizedCockpitAction(form.action, fallback: selectedTool?.descriptor.defaultAction ?? "run")
            if selectedAction == "apply" {
                let history = await CockpitCanonicalLauncher.history(limit: 25, on: req.db, logger: req.logger)
                if let blockingGuardReason = latestBlockingGuardReason(in: history.entries, logger: req.logger) {
                    throw Abort(.badRequest, reason: "Apply bloqué par un diagnostic prioritaire blocking: \(blockingGuardReason)")
                }
            }

            let parameters = try parseParametersJSON(form.parameters_json)
            let inputArtifacts = try parseInputArtifactsJSON(form.input_artifacts_json)
            let launchRequest = CockpitLaunchRequest(
                toolID: toolID,
                action: selectedAction,
                correlationID: req.headers.first(name: "x-correlation-id"),
                workspacePath: nonEmpty(form.workspace_path),
                inputArtifacts: inputArtifacts,
                parameters: parameters,
                allowDestructive: parseBooleanFlag(form.allow_destructive, defaultValue: false)
            )

            let outcome = try await CockpitCanonicalLauncher.launch(launchRequest, on: req.db, logger: req.logger)
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
    app.get("ui", "muni") { req async throws -> Response in
        req.redirect(to: "/ui/muni/store")
    }
    app.get("ui", "muni", "store") { req async throws -> View in
        let context = try await buildMuniStoreContext(req)
        return try await req.view.render("muni_store", context)
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
    app.get("ui", "muni", "apps", "MuniRenommage") { req async throws -> View in
        let context = try await buildMuniAppContext(req)
        return try await req.view.render("muni_app", context)
    }
    app.get("ui", "muni", "apps", "MuniConversion") { req async throws -> View in
        let context = try await buildMuniAppContext(req)
        return try await req.view.render("muni_app", context)
    }
    app.get("ui", "muni", "apps", ":id") { req async throws -> View in
        let context = try await buildMuniAppContext(req)
        return try await req.view.render("muni_app", context)
    }

    app.on(.POST, "ui", "cockpit", "run", body: .collect(maxSize: "2mb"), use: runPilotage)
    app.on(.POST, "ui", "pilotage", "run", body: .collect(maxSize: "2mb"), use: runPilotage)
}

private func muniStoreVisibleState(
    for descriptor: CockpitToolDescriptor,
    runtimeTool: CockpitToolRuntimeDescriptor?
) -> (label: String, cssClass: String) {
    guard descriptor.enabled else {
        return ("desactive", "state-disabled")
    }
    guard let runtimeTool else {
        return ("erreur", "state-error")
    }
    if runtimeTool.isAvailable {
        return ("active", "state-active")
    }
    return ("non disponible", "state-unavailable")
}

private func muniStoreEmployeeReadiness(for appID: String) -> (label: String, cssClass: String, reason: String) {
    if employeeFacadeURL(for: appID) != nil {
        return (
            "Prêt employé",
            "employee-ready",
            "Façade employé dédiée et point d'entrée App Store disponibles."
        )
    }
    return (
        "Technique seulement",
        "employee-technical",
        "Aucune façade employé stabilisée pour ce module."
    )
}

private func muniStoreActions(for appID: String) -> [UIMuniStoreAction] {
    let employeeURL = employeeFacadeURL(for: appID)
    return [
        UIMuniStoreAction(
            action_key: "ouvrir",
            action_label: "Ouvrir l’outil",
            action_url: employeeURL ?? "#",
            is_disabled: employeeURL == nil,
            is_primary: true,
            action_class: "primary",
            disabled_reason: employeeURL == nil ? "Façade employé non disponible." : ""
        ),
        UIMuniStoreAction(
            action_key: "voir_details",
            action_label: "Voir la fiche",
            action_url: "/ui/muni/apps/\(urlPathComponentEncoded(appID))",
            is_disabled: false,
            is_primary: false,
            action_class: "",
            disabled_reason: ""
        ),
        UIMuniStoreAction(
            action_key: "activer",
            action_label: "Activer",
            action_url: "#",
            is_disabled: true,
            is_primary: false,
            action_class: "",
            disabled_reason: "Activation non disponible à ce stade."
        ),
        UIMuniStoreAction(
            action_key: "desactiver",
            action_label: "Désactiver",
            action_url: "#",
            is_disabled: true,
            is_primary: false,
            action_class: "",
            disabled_reason: "Désactivation non disponible à ce stade."
        )
    ]
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
        collisionCount: intValue(from: metadata["collision_count"]),
        idempotentCount: intValue(from: metadata["idempotent_count"]),
        planDigest: stringValue(from: metadata["plan_digest"]),
        errors: extractErrorLabels(fromResultRoot: resultRoot),
        warnings: warnings
    )
}

private func prioritizedDiagnostic(
    for entry: CockpitHistoryEntry,
    diagnostics: UICockpitHistoryDiagnostics
) -> UICockpitPriorityDiagnosticSummary? {
    let status = entry.status
    let summary = (entry.summary ?? "").lowercased()
    let fallbackReason = (diagnostics.reglesFallbackReason ?? "").lowercased()
    let errorsText = diagnostics.errors.joined(separator: " ").lowercased()
    let destinationExistsSignal =
        summary.contains("destination_exists") ||
        summary.contains("destination already exists") ||
        summary.contains("destination existante") ||
        errorsText.contains("destination_exists") ||
        errorsText.contains("destination already exists") ||
        errorsText.contains("destination existante")

    if diagnostics.collisionCount ?? 0 > 0 ||
        summary.contains("collision") ||
        errorsText.contains("collision") ||
        destinationExistsSignal {
        return UICockpitPriorityDiagnosticSummary(
            id: "RN_COLLISION_BLOCKING",
            label: "Collision bloquante / destination existante",
            severity: "blocking",
            severityLabel: "Blocking",
            cta: "Stop Apply"
        )
    }

    if summary.contains("expected_plan_digest") ||
        summary.contains("digest") ||
        errorsText.contains("expected_plan_digest") ||
        errorsText.contains("plan_digest") {
        return UICockpitPriorityDiagnosticSummary(
            id: "RN_PLAN_DIGEST_MISMATCH",
            label: "Digest preview/apply incohérent",
            severity: "blocking",
            severityLabel: "Blocking",
            cta: "Re-preview"
        )
    }

    if summary.contains("allow_destructive") || summary.contains("confirm_apply") || errorsText.contains("allow_destructive") {
        return UICockpitPriorityDiagnosticSummary(
            id: "RN_DESTRUCTIVE_GUARD_MISSING",
            label: "Garde-fou apply manquant",
            severity: "blocking",
            severityLabel: "Blocking",
            cta: "Stop Apply"
        )
    }

    if fallbackReason == "required_metadata_fields_missing" ||
        summary.contains("required_metadata_fields") ||
        errorsText.contains("required_metadata_fields") {
        return UICockpitPriorityDiagnosticSummary(
            id: "RG_REQUIRED_METADATA_FIELDS_MISSING",
            label: "Metadata requises manquantes",
            severity: "blocking",
            severityLabel: "Blocking",
            cta: "Re-run Analyse"
        )
    }

    if ["bundle_unreadable_or_invalid", "bundle_has_no_naming_rules"].contains(fallbackReason) {
        return UICockpitPriorityDiagnosticSummary(
            id: "RG_BUNDLE_UNREADABLE_OR_INVALID",
            label: "Bundle règles invalide",
            severity: "blocking",
            severityLabel: "Blocking",
            cta: "Rebuild Bundle"
        )
    }

    if ["naming_rule_not_found", "template_not_supported", "naming_rule_id_missing", "class_code_missing", "document_metadata_not_provided"].contains(fallbackReason) {
        return UICockpitPriorityDiagnosticSummary(
            id: "RG_RULE_NOT_FOUND_OR_NOT_APPLICABLE",
            label: "Règle absente ou non applicable",
            severity: "blocking",
            severityLabel: "Blocking",
            cta: "Re-preview"
        )
    }

    if !fallbackReason.isEmpty {
        return UICockpitPriorityDiagnosticSummary(
            id: "RG_FALLBACK_REASON_PRESENT",
            label: "Fallback règle: \(fallbackReason)",
            severity: "warning",
            severityLabel: "Warning",
            cta: "Re-preview"
        )
    }

    if !diagnostics.warnings.isEmpty {
        return UICockpitPriorityDiagnosticSummary(
            id: "AN_EXTRACTION_WARNING_STRUCTURED",
            label: "Qualité extraction à vérifier",
            severity: "warning",
            severityLabel: "Warning",
            cta: "Re-run Analyse"
        )
    }

    if diagnostics.extractionProvenance?.lowercased() == "filename_fallback" {
        return UICockpitPriorityDiagnosticSummary(
            id: "AN_EXTRACTION_PROVENANCE_FALLBACK",
            label: "Extraction en provenance fallback",
            severity: "warning",
            severityLabel: "Warning",
            cta: "Re-run Analyse"
        )
    }

    if diagnostics.idempotentCount ?? 0 > 0, status == .succeeded {
        return UICockpitPriorityDiagnosticSummary(
            id: "RN_IDEMPOTENT_NOOP",
            label: "Aucun changement requis (no-op)",
            severity: "info",
            severityLabel: "Info",
            cta: nil
        )
    }

    if status == .failed {
        return UICockpitPriorityDiagnosticSummary(
            id: "RN_EXECUTION_FAILED",
            label: "Échec d'exécution à revoir",
            severity: "warning",
            severityLabel: "Warning",
            cta: "Re-preview"
        )
    }

    return nil
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

private func latestBlockingGuardReason(
    in historyEntries: [CockpitHistoryEntry],
    logger: Logger
) -> String? {
    for entry in historyEntries {
        let diagnostics = loadHistoryDiagnostics(for: entry, logger: logger)
        guard let priorityDiagnostic = prioritizedDiagnostic(for: entry, diagnostics: diagnostics),
              priorityDiagnostic.isBlocking else {
            continue
        }
        return "[\(priorityDiagnostic.id)] \(priorityDiagnostic.label)"
    }

    return nil
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

private func extractErrorLabels(fromResultRoot root: [String: Any]) -> [String] {
    guard let errors = root["errors"] as? [[String: Any]] else {
        return []
    }
    return errors.compactMap { error in
        if let code = stringValue(from: error["code"]) {
            return code
        }
        return stringValue(from: error["message"])
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

private func normalizedCockpitAction(_ rawAction: String?, fallback: String) -> String {
    let fallbackValue = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = rawAction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return candidate.isEmpty ? fallbackValue : candidate
}

private func employeeDetailURL(for appID: String) -> String {
    employeeFacadeURL(for: appID) ?? "/ui/muni/apps/\(urlPathComponentEncoded(appID))"
}

private func employeeFacadeURL(for appID: String) -> String? {
    switch appID {
    case "MuniRenommage":
        return "/ui/muni/apps/MuniRenommage/employe"
    case "MuniConversion":
        return "/ui/muni/apps/MuniConversion/employe"
    default:
        return nil
    }
}

private func explicitMuniAppID(for path: String) -> String? {
    switch path {
    case "/ui/muni/apps/MuniRenommage":
        return "MuniRenommage"
    case "/ui/muni/apps/MuniConversion":
        return "MuniConversion"
    default:
        return nil
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

private func uiDiagnosticSeverityLabel(_ severity: String?) -> String {
    switch severity {
    case "blocking":
        return "Blocking"
    case "warning":
        return "Warning"
    default:
        return "Info"
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

private func urlPathComponentEncoded(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
}
