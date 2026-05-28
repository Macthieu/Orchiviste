import Fluent
import Foundation
import OrchivisteKitContracts
import Vapor

private struct UIMuniAnalyseEmployeeForm: Content {
    let source_mode: String?
    let source_text: String?
    let source_path: String?
}

private struct UIMuniAnalyseRecentRun: Encodable {
    let execution_id: String
    let status_label: String
    let status_class: String
    let finished_at: String
    let summary: String
    let view_url: String
}

private struct UIMuniAnalyseTopTerm: Encodable {
    let term: String
    let occurrences: String
}

private struct UIMuniAnalyseResultError: Encodable {
    let code: String
    let message: String
}

private struct UIMuniAnalyseEmployeeContext: Encodable {
    let source_mode_text_checked_attr: String
    let source_mode_file_checked_attr: String
    let source_text: String
    let source_path: String
    let availability_label: String
    let availability_class: String
    let availability_reason: String
    let result_present: Bool
    let result_execution_id: String
    let result_status_label: String
    let result_status_class: String
    let result_summary: String
    let result_finished_at: String
    let result_source_kind: String
    let result_character_count: String
    let result_word_count: String
    let result_sentence_count: String
    let result_paragraph_count: String
    let result_preview: String
    let result_preview_present: Bool
    let result_top_terms: [UIMuniAnalyseTopTerm]
    let result_top_terms_present: Bool
    let result_warnings: [String]
    let result_warnings_present: Bool
    let result_errors: [UIMuniAnalyseResultError]
    let result_errors_present: Bool
    let result_file_path: String
    let result_file_url: String
    let recent_runs: [UIMuniAnalyseRecentRun]
    let recent_runs_present: Bool
    let technical_app_url: String
    let expert_launch_url: String
    let back_to_store_url: String
    let notice: String?
    let error: String?
}

private struct MuniAnalyseResultSnapshot {
    let executionID: String
    let statusLabel: String
    let statusClass: String
    let summary: String
    let finishedAt: String
    let resultFilePath: String
    let metadata: MuniAnalyseResultMetadata
    let errors: [UIMuniAnalyseResultError]
}

private struct MuniAnalyseResultMetadata {
    let sourceKind: String?
    let characterCount: Int?
    let wordCount: Int?
    let sentenceCount: Int?
    let paragraphCount: Int?
    let preview: String?
    let topTerms: [UIMuniAnalyseTopTerm]
    let warnings: [String]

    static let empty = MuniAnalyseResultMetadata(
        sourceKind: nil,
        characterCount: nil,
        wordCount: nil,
        sentenceCount: nil,
        paragraphCount: nil,
        preview: nil,
        topTerms: [],
        warnings: []
    )
}

func registerMuniAnalyseEmployeeUIRoutes(_ app: Application) {
    let buildContext: @Sendable (Request) async throws -> UIMuniAnalyseEmployeeContext = { req in
        let sourceMode = normalizedMuniAnalyseSourceMode(req.query[String.self, at: "source_mode"])
        let sourceText = nonEmptyMuniAnalyseValue(req.query[String.self, at: "source_text"]) ?? ""
        let sourcePath = nonEmptyMuniAnalyseValue(req.query[String.self, at: "source_path"]) ?? ""
        let requestedExecutionID = nonEmptyMuniAnalyseValue(req.query[String.self, at: "execution_id"])

        let runtime = await CockpitCanonicalLauncher.loadRuntimeCatalog(on: req.db, logger: req.logger)
        let runtimeTool = runtime.tools.first(where: { $0.descriptor.id == "MuniAnalyse" })
        let isAvailable = runtimeTool?.isAvailable == true
        let availabilityLabel = isAvailable ? "Prêt" : "Indisponible"
        let availabilityClass = isAvailable ? "pill-ok" : "pill-warn"
        let availabilityReason = isAvailable
            ? "Le service d'analyse texte est disponible."
            : (runtimeTool?.availabilityReason ?? "Disponibilité non déterminée.")

        let recentEntries = try await CockpitRegistryRepository.listRecentRuns(appID: "MuniAnalyse", limit: 12, on: req.db)
        let selectedEntry = requestedExecutionID.flatMap { executionID in
            recentEntries.first(where: { $0.executionID == executionID })
        }

        var resultSnapshot: MuniAnalyseResultSnapshot?
        if let selectedEntry {
            let resultRoot = muniAnalyseReadJSONObject(atPath: selectedEntry.resultFile, logger: req.logger)
            resultSnapshot = MuniAnalyseResultSnapshot(
                executionID: selectedEntry.executionID,
                statusLabel: muniAnalyseStatusLabel(selectedEntry.status),
                statusClass: muniAnalyseStatusClass(selectedEntry.status),
                summary: muniAnalyseSummary(selectedEntry.summary),
                finishedAt: selectedEntry.finishedAt,
                resultFilePath: selectedEntry.resultFile,
                metadata: loadMuniAnalyseResultMetadata(resultRoot: resultRoot),
                errors: loadMuniAnalyseResultErrors(resultRoot: resultRoot)
            )
        }

        let recentRuns = recentEntries.prefix(6).map { entry in
            UIMuniAnalyseRecentRun(
                execution_id: entry.executionID,
                status_label: muniAnalyseStatusLabel(entry.status),
                status_class: muniAnalyseStatusClass(entry.status),
                finished_at: entry.finishedAt,
                summary: muniAnalyseSummary(entry.summary),
                view_url: employeeMuniAnalysePageURL(
                    sourceMode: sourceMode,
                    sourcePath: sourcePath,
                    executionID: entry.executionID
                )
            )
        }

        return UIMuniAnalyseEmployeeContext(
            source_mode_text_checked_attr: sourceMode == "text" ? "checked" : "",
            source_mode_file_checked_attr: sourceMode == "file" ? "checked" : "",
            source_text: sourceText,
            source_path: sourcePath,
            availability_label: availabilityLabel,
            availability_class: availabilityClass,
            availability_reason: availabilityReason,
            result_present: resultSnapshot != nil,
            result_execution_id: resultSnapshot?.executionID ?? "",
            result_status_label: resultSnapshot?.statusLabel ?? "",
            result_status_class: resultSnapshot?.statusClass ?? "status-info",
            result_summary: resultSnapshot?.summary ?? "",
            result_finished_at: resultSnapshot?.finishedAt ?? "",
            result_source_kind: muniAnalyseSourceKindLabel(resultSnapshot?.metadata.sourceKind),
            result_character_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.characterCount),
            result_word_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.wordCount),
            result_sentence_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.sentenceCount),
            result_paragraph_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.paragraphCount),
            result_preview: resultSnapshot?.metadata.preview ?? "",
            result_preview_present: resultSnapshot?.metadata.preview != nil,
            result_top_terms: resultSnapshot?.metadata.topTerms ?? [],
            result_top_terms_present: !(resultSnapshot?.metadata.topTerms ?? []).isEmpty,
            result_warnings: resultSnapshot?.metadata.warnings ?? [],
            result_warnings_present: !(resultSnapshot?.metadata.warnings ?? []).isEmpty,
            result_errors: resultSnapshot?.errors ?? [],
            result_errors_present: !(resultSnapshot?.errors ?? []).isEmpty,
            result_file_path: resultSnapshot?.resultFilePath ?? "",
            result_file_url: resultSnapshot.map { employeeMuniAnalyseResultFileURL(executionID: $0.executionID) } ?? "",
            recent_runs: Array(recentRuns),
            recent_runs_present: !recentRuns.isEmpty,
            technical_app_url: "/ui/muni/apps/MuniAnalyse",
            expert_launch_url: "/ui/pilotage/lancer?tool=MuniAnalyse",
            back_to_store_url: "/ui/muni/store",
            notice: nonEmptyMuniAnalyseValue(req.query[String.self, at: "notice"]),
            error: nonEmptyMuniAnalyseValue(req.query[String.self, at: "error"])
        )
    }

    app.get("ui", "muni", "apps", "MuniAnalyse", "employe") { req async throws -> View in
        let context = try await buildContext(req)
        return try await req.view.render("muni_analyse_employee", context)
    }

    app.get("ui", "muni", "apps", "MuniAnalyse", "employe", "result", ":executionID") { req async throws -> Response in
        guard let executionID = nonEmptyMuniAnalyseValue(req.parameters.get("executionID")) else {
            throw Abort(.badRequest, reason: "Identifiant d'exécution manquant.")
        }
        let entry = try await fetchMuniAnalyseRun(executionID: executionID, on: req.db)
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

    app.on(.POST, "ui", "muni", "apps", "MuniAnalyse", "employe", "run", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        let form = try req.content.decode(UIMuniAnalyseEmployeeForm.self)
        let sourceMode = normalizedMuniAnalyseSourceMode(form.source_mode)
        let sourcePathForRedirect = nonEmptyMuniAnalyseValue(form.source_path) ?? ""

        do {
            let parameters = try muniAnalyseParameters(form: form, sourceMode: sourceMode)
            let launchRequest = CockpitLaunchRequest(
                toolID: "MuniAnalyse",
                action: "analyze",
                correlationID: req.headers.first(name: "x-correlation-id"),
                workspacePath: nil,
                inputArtifacts: [],
                parameters: parameters,
                allowDestructive: false
            )

            let outcome = try await CockpitCanonicalLauncher.launch(launchRequest, on: req.db, logger: req.logger)
            return req.redirect(to: employeeMuniAnalysePageURL(
                sourceMode: sourceMode,
                sourcePath: sourcePathForRedirect,
                executionID: outcome.executionID,
                notice: "Analyse \(outcome.executionID) terminée."
            ))
        } catch let abort as AbortError {
            return req.redirect(to: employeeMuniAnalysePageURL(
                sourceMode: sourceMode,
                sourcePath: sourcePathForRedirect,
                executionID: nil,
                error: abort.reason.isEmpty ? "Échec exécution MuniAnalyse." : abort.reason
            ))
        } catch {
            req.logger.error("Échec façade employé MuniAnalyse.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: employeeMuniAnalysePageURL(
                sourceMode: sourceMode,
                sourcePath: sourcePathForRedirect,
                executionID: nil,
                error: "Erreur interne pendant l'exécution de MuniAnalyse."
            ))
        }
    }
}

private func muniAnalyseParameters(form: UIMuniAnalyseEmployeeForm, sourceMode: String) throws -> [String: JSONValue] {
    switch sourceMode {
    case "file":
        let sourcePath = try validatedMuniAnalyseTextFilePath(form.source_path)
        return [
            "text": .string(""),
            "source_path": .string(sourcePath)
        ]
    default:
        guard let sourceText = nonEmptyMuniAnalyseValue(form.source_text) else {
            throw Abort(.badRequest, reason: "Le texte à analyser est requis.")
        }
        return ["text": .string(sourceText)]
    }
}

private func validatedMuniAnalyseTextFilePath(_ rawValue: String?) throws -> String {
    guard let rawValue, let path = normalizedMuniEmployeePathInput(rawValue) else {
        throw Abort(.badRequest, reason: "Le fichier source est requis.")
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        throw Abort(.badRequest, reason: "Le fichier source doit exister et être accessible.")
    }
    return URL(fileURLWithPath: path).standardizedFileURL.path
}

private func fetchMuniAnalyseRun(executionID: String, on db: Database) async throws -> CockpitHistoryEntry {
    let entries = try await CockpitRegistryRepository.listRecentRuns(appID: "MuniAnalyse", limit: 50, on: db)
    guard let entry = entries.first(where: { $0.executionID == executionID }) else {
        throw Abort(.notFound, reason: "Run MuniAnalyse introuvable.")
    }
    return entry
}

private func employeeMuniAnalysePageURL(
    sourceMode: String,
    sourcePath: String,
    executionID: String?,
    notice: String? = nil,
    error: String? = nil
) -> String {
    var params: [String] = ["source_mode=\(muniAnalyseURLQueryEncoded(sourceMode))"]
    if !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        params.append("source_path=\(muniAnalyseURLQueryEncoded(sourcePath))")
    }
    if let executionID {
        params.append("execution_id=\(muniAnalyseURLQueryEncoded(executionID))")
    }
    if let notice {
        params.append("notice=\(muniAnalyseURLQueryEncoded(notice))")
    }
    if let error {
        params.append("error=\(muniAnalyseURLQueryEncoded(error))")
    }
    return "/ui/muni/apps/MuniAnalyse/employe?\(params.joined(separator: "&"))"
}

private func employeeMuniAnalyseResultFileURL(executionID: String) -> String {
    "/ui/muni/apps/MuniAnalyse/employe/result/\(muniAnalyseURLPathEncoded(executionID))"
}

private func loadMuniAnalyseResultMetadata(resultRoot: [String: Any]?) -> MuniAnalyseResultMetadata {
    guard let metadata = resultRoot?["metadata"] as? [String: Any] else {
        return .empty
    }

    let topTerms = (metadata["top_terms"] as? [[String: Any]] ?? []).prefix(8).compactMap { item -> UIMuniAnalyseTopTerm? in
        guard let term = muniAnalyseStringValue(from: item["term"]) else {
            return nil
        }
        return UIMuniAnalyseTopTerm(
            term: term,
            occurrences: muniAnalyseStringOrDash(muniAnalyseIntValue(from: item["occurrences"]))
        )
    }

    let warnings = (metadata["warnings"] as? [Any] ?? []).compactMap(muniAnalyseStringValue)

    return MuniAnalyseResultMetadata(
        sourceKind: muniAnalyseStringValue(from: metadata["source_kind"]),
        characterCount: muniAnalyseIntValue(from: metadata["character_count"]),
        wordCount: muniAnalyseIntValue(from: metadata["word_count"]),
        sentenceCount: muniAnalyseIntValue(from: metadata["sentence_count"]),
        paragraphCount: muniAnalyseIntValue(from: metadata["paragraph_count"]),
        preview: muniAnalyseStringValue(from: metadata["preview"]),
        topTerms: Array(topTerms),
        warnings: warnings
    )
}

private func loadMuniAnalyseResultErrors(resultRoot: [String: Any]?) -> [UIMuniAnalyseResultError] {
    let errors = resultRoot?["errors"] as? [[String: Any]] ?? []
    return errors.prefix(5).map { error in
        UIMuniAnalyseResultError(
            code: muniAnalyseStringValue(from: error["code"]) ?? "ERROR",
            message: muniAnalyseStringValue(from: error["message"]) ?? "Erreur non détaillée."
        )
    }
}

private func muniAnalyseReadJSONObject(atPath path: String, logger: Logger) -> [String: Any]? {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
    }

    do {
        let data = try Data(contentsOf: fileURL)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    } catch {
        logger.debug("Lecture JSON MuniAnalyse employé ignorée.", metadata: [
            "path": .string(fileURL.path),
            "error": .string(error.localizedDescription)
        ])
        return nil
    }
}

private func normalizedMuniAnalyseSourceMode(_ rawValue: String?) -> String {
    nonEmptyMuniAnalyseValue(rawValue)?.lowercased() == "file" ? "file" : "text"
}

private func nonEmptyMuniAnalyseValue(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func muniAnalyseStringValue(from rawValue: Any?) -> String? {
    guard let rawValue else {
        return nil
    }
    if let text = rawValue as? String {
        return nonEmptyMuniAnalyseValue(text)
    }
    if let number = rawValue as? NSNumber {
        return number.stringValue
    }
    return nil
}

private func muniAnalyseIntValue(from rawValue: Any?) -> Int? {
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

private func muniAnalyseStringOrDash(_ value: Int?) -> String {
    value.map(String.init) ?? "-"
}

private func muniAnalyseSourceKindLabel(_ sourceKind: String?) -> String {
    switch sourceKind {
    case "source_path":
        return "Fichier texte"
    case "input_artifact":
        return "Artefact fichier"
    case "inline_text":
        return "Texte collé"
    default:
        return "-"
    }
}

private func muniAnalyseStatusLabel(_ status: ToolStatus) -> String {
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

private func muniAnalyseStatusClass(_ status: ToolStatus) -> String {
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

private func muniAnalyseSummary(_ rawSummary: String?) -> String {
    switch rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "Text analysis completed successfully.":
        return "Analyse texte terminée avec succès."
    case "Text analysis completed with review warnings.":
        return "Analyse texte terminée avec points à revoir."
    case let value? where !value.isEmpty:
        return value
    default:
        return "Aucun résumé disponible."
    }
}

private func muniAnalyseURLQueryEncoded(_ value: String) -> String {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func muniAnalyseURLPathEncoded(_ value: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
