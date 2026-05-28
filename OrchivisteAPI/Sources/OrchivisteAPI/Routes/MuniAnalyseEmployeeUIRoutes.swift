import Fluent
import Foundation
import OrchivisteKitContracts
import Vapor

private struct UIMuniAnalyseEmployeeForm: Content {
    let source_mode: String?
    let source_text: String?
    let source_path: String?
    let source_document_path: String?
    let source_document_path_mode: String?
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

private struct UIMuniAnalyseResultWarning: Encodable {
    let code: String
    let message: String
    let source_file: String
}

private struct UIMuniAnalyseDocumentItem: Encodable {
    let source_file: String
    let document_type: String
    let document_subject: String
    let document_date: String
    let provenance: String
    let warning_count: String
}

private struct UIMuniAnalyseEmployeeContext: Encodable {
    let source_mode_text_checked_attr: String
    let source_mode_file_checked_attr: String
    let source_mode_documents_checked_attr: String
    let source_text: String
    let source_path: String
    let source_document_path: String
    let availability_label: String
    let availability_class: String
    let availability_reason: String
    let result_present: Bool
    let result_execution_id: String
    let result_status_label: String
    let result_status_class: String
    let result_summary: String
    let result_finished_at: String
    let result_mode_label: String
    let result_source_kind: String
    let result_character_count: String
    let result_word_count: String
    let result_sentence_count: String
    let result_paragraph_count: String
    let result_source_count: String
    let result_documents_extracted: String
    let result_warning_count: String
    let result_preview: String
    let result_preview_present: Bool
    let result_top_terms: [UIMuniAnalyseTopTerm]
    let result_top_terms_present: Bool
    let result_documents: [UIMuniAnalyseDocumentItem]
    let result_documents_present: Bool
    let result_warnings: [UIMuniAnalyseResultWarning]
    let result_warnings_present: Bool
    let result_errors: [UIMuniAnalyseResultError]
    let result_errors_present: Bool
    let result_file_path: String
    let result_file_url: String
    let result_document_metadata_path: String
    let result_document_metadata_url: String
    let result_document_metadata_present: Bool
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
    let sourceCount: Int?
    let documentsExtracted: Int?
    let warningCount: Int?
    let mode: String?
    let documentMetadataOutputPath: String?
    let preview: String?
    let topTerms: [UIMuniAnalyseTopTerm]
    let documents: [UIMuniAnalyseDocumentItem]
    let warnings: [UIMuniAnalyseResultWarning]

    static let empty = MuniAnalyseResultMetadata(
        sourceKind: nil,
        characterCount: nil,
        wordCount: nil,
        sentenceCount: nil,
        paragraphCount: nil,
        sourceCount: nil,
        documentsExtracted: nil,
        warningCount: nil,
        mode: nil,
        documentMetadataOutputPath: nil,
        preview: nil,
        topTerms: [],
        documents: [],
        warnings: []
    )
}

func registerMuniAnalyseEmployeeUIRoutes(_ app: Application) {
    let buildContext: @Sendable (Request) async throws -> UIMuniAnalyseEmployeeContext = { req in
        let sourceMode = normalizedMuniAnalyseSourceMode(req.query[String.self, at: "source_mode"])
        let sourceText = nonEmptyMuniAnalyseValue(req.query[String.self, at: "source_text"]) ?? ""
        let sourcePath = nonEmptyMuniAnalyseValue(req.query[String.self, at: "source_path"]) ?? ""
        let sourceDocumentPath = nonEmptyMuniAnalyseValue(req.query[String.self, at: "source_document_path"]) ?? ""
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
                metadata: loadMuniAnalyseResultMetadata(resultRoot: resultRoot, logger: req.logger),
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
                    sourceDocumentPath: sourceDocumentPath,
                    executionID: entry.executionID
                )
            )
        }

        let documentMetadataPath = resultSnapshot?.metadata.documentMetadataOutputPath ?? ""
        let documentMetadataPresent = !documentMetadataPath.isEmpty
            && FileManager.default.fileExists(atPath: documentMetadataPath)

        return UIMuniAnalyseEmployeeContext(
            source_mode_text_checked_attr: sourceMode == "text" ? "checked" : "",
            source_mode_file_checked_attr: sourceMode == "file" ? "checked" : "",
            source_mode_documents_checked_attr: sourceMode == "documents" ? "checked" : "",
            source_text: sourceText,
            source_path: sourcePath,
            source_document_path: sourceDocumentPath,
            availability_label: availabilityLabel,
            availability_class: availabilityClass,
            availability_reason: availabilityReason,
            result_present: resultSnapshot != nil,
            result_execution_id: resultSnapshot?.executionID ?? "",
            result_status_label: resultSnapshot?.statusLabel ?? "",
            result_status_class: resultSnapshot?.statusClass ?? "status-info",
            result_summary: resultSnapshot?.summary ?? "",
            result_finished_at: resultSnapshot?.finishedAt ?? "",
            result_mode_label: muniAnalyseModeLabel(resultSnapshot?.metadata.mode),
            result_source_kind: muniAnalyseDisplayedSourceKind(resultSnapshot?.metadata),
            result_character_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.characterCount),
            result_word_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.wordCount),
            result_sentence_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.sentenceCount),
            result_paragraph_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.paragraphCount),
            result_source_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.sourceCount),
            result_documents_extracted: muniAnalyseStringOrDash(resultSnapshot?.metadata.documentsExtracted),
            result_warning_count: muniAnalyseStringOrDash(resultSnapshot?.metadata.warningCount),
            result_preview: resultSnapshot?.metadata.preview ?? "",
            result_preview_present: resultSnapshot?.metadata.preview != nil,
            result_top_terms: resultSnapshot?.metadata.topTerms ?? [],
            result_top_terms_present: !(resultSnapshot?.metadata.topTerms ?? []).isEmpty,
            result_documents: resultSnapshot?.metadata.documents ?? [],
            result_documents_present: !(resultSnapshot?.metadata.documents ?? []).isEmpty,
            result_warnings: resultSnapshot?.metadata.warnings ?? [],
            result_warnings_present: !(resultSnapshot?.metadata.warnings ?? []).isEmpty,
            result_errors: resultSnapshot?.errors ?? [],
            result_errors_present: !(resultSnapshot?.errors ?? []).isEmpty,
            result_file_path: resultSnapshot?.resultFilePath ?? "",
            result_file_url: resultSnapshot.map { employeeMuniAnalyseResultFileURL(executionID: $0.executionID) } ?? "",
            result_document_metadata_path: documentMetadataPath,
            result_document_metadata_url: resultSnapshot.map {
                employeeMuniAnalyseDocumentMetadataFileURL(executionID: $0.executionID)
            } ?? "",
            result_document_metadata_present: documentMetadataPresent,
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

    app.get("ui", "muni", "apps", "MuniAnalyse", "employe", "document-metadata", ":executionID") { req async throws -> Response in
        guard let executionID = nonEmptyMuniAnalyseValue(req.parameters.get("executionID")) else {
            throw Abort(.badRequest, reason: "Identifiant d'exécution manquant.")
        }
        let entry = try await fetchMuniAnalyseRun(executionID: executionID, on: req.db)
        let resultRoot = muniAnalyseReadJSONObject(atPath: entry.resultFile, logger: req.logger)
        let metadata = loadMuniAnalyseResultMetadata(resultRoot: resultRoot, logger: req.logger)
        guard let outputPath = metadata.documentMetadataOutputPath else {
            throw Abort(.notFound, reason: "Le fichier de métadonnées documentaires est indisponible.")
        }

        let fileURL = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw Abort(.notFound, reason: "Le fichier de métadonnées documentaires est indisponible.")
        }

        let response = try await req.fileio.asyncStreamFile(at: fileURL.path)
        response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
        response.headers.replaceOrAdd(
            name: .contentDisposition,
            value: "inline; filename=\"\(fileURL.lastPathComponent)\""
        )
        return response
    }

    app.on(.POST, "ui", "muni", "apps", "MuniAnalyse", "employe", "run", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        let form = try req.content.decode(UIMuniAnalyseEmployeeForm.self)
        let sourceMode = normalizedMuniAnalyseSourceMode(form.source_mode)
        let sourcePathForRedirect = nonEmptyMuniAnalyseValue(form.source_path) ?? ""
        let sourceDocumentPathForRedirect = nonEmptyMuniAnalyseValue(form.source_document_path) ?? ""

        do {
            let runtimeConfig = CockpitConfigLoader.load(logger: req.logger)
            let parameters = try muniAnalyseParameters(
                form: form,
                sourceMode: sourceMode,
                runtimeConfig: runtimeConfig
            )
            let launchRequest = CockpitLaunchRequest(
                toolID: "MuniAnalyse",
                action: sourceMode == "documents" ? "extract-metadata" : "analyze",
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
                sourceDocumentPath: sourceDocumentPathForRedirect,
                executionID: outcome.executionID,
                notice: "Analyse \(outcome.executionID) terminée."
            ))
        } catch let abort as AbortError {
            return req.redirect(to: employeeMuniAnalysePageURL(
                sourceMode: sourceMode,
                sourcePath: sourcePathForRedirect,
                sourceDocumentPath: sourceDocumentPathForRedirect,
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
                sourceDocumentPath: sourceDocumentPathForRedirect,
                executionID: nil,
                error: "Erreur interne pendant l'exécution de MuniAnalyse."
            ))
        }
    }
}

private func muniAnalyseParameters(
    form: UIMuniAnalyseEmployeeForm,
    sourceMode: String,
    runtimeConfig: CockpitConfig
) throws -> [String: JSONValue] {
    switch sourceMode {
    case "file":
        let sourcePath = try validatedMuniAnalyseTextFilePath(form.source_path)
        return [
            "text": .string(""),
            "source_path": .string(sourcePath)
        ]
    case "documents":
        let sourcePath = try validatedMuniAnalyseDocumentSourcePath(form.source_document_path)
        let outputPath = try makeMuniAnalyseDocumentMetadataOutputPath(runtimeConfig: runtimeConfig)
        return [
            "extract_document_metadata": .bool(true),
            "source_paths": .array([.string(sourcePath)]),
            "document_metadata_output_path": .string(outputPath)
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

private func validatedMuniAnalyseDocumentSourcePath(_ rawValue: String?) throws -> String {
    guard let rawValue, let path = normalizedMuniEmployeePathInput(rawValue) else {
        throw Abort(.badRequest, reason: "Le fichier ou dossier documentaire est requis.")
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
        throw Abort(.badRequest, reason: "Le fichier ou dossier documentaire doit exister et être accessible.")
    }
    return URL(fileURLWithPath: path).standardizedFileURL.path
}

private func makeMuniAnalyseDocumentMetadataOutputPath(runtimeConfig: CockpitConfig) throws -> String {
    let resultsURL = URL(fileURLWithPath: runtimeConfig.resultsDirectory, isDirectory: true)
    try FileManager.default.createDirectory(at: resultsURL, withIntermediateDirectories: true)
    return resultsURL
        .appendingPathComponent("muni-analyse-document-metadata-\(UUID().uuidString).json")
        .path
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
    sourceDocumentPath: String,
    executionID: String?,
    notice: String? = nil,
    error: String? = nil
) -> String {
    var params: [String] = ["source_mode=\(muniAnalyseURLQueryEncoded(sourceMode))"]
    if !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        params.append("source_path=\(muniAnalyseURLQueryEncoded(sourcePath))")
    }
    if !sourceDocumentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        params.append("source_document_path=\(muniAnalyseURLQueryEncoded(sourceDocumentPath))")
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

private func employeeMuniAnalyseDocumentMetadataFileURL(executionID: String) -> String {
    "/ui/muni/apps/MuniAnalyse/employe/document-metadata/\(muniAnalyseURLPathEncoded(executionID))"
}

private func loadMuniAnalyseResultMetadata(resultRoot: [String: Any]?, logger: Logger) -> MuniAnalyseResultMetadata {
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

    let outputPath = muniAnalyseStringValue(from: metadata["document_metadata_output_path"])
    let documents = loadMuniAnalyseDocumentItems(atPath: outputPath, logger: logger)
    let warnings = loadMuniAnalyseResultWarnings(from: metadata["warnings"])

    return MuniAnalyseResultMetadata(
        sourceKind: muniAnalyseStringValue(from: metadata["source_kind"]),
        characterCount: muniAnalyseIntValue(from: metadata["character_count"]),
        wordCount: muniAnalyseIntValue(from: metadata["word_count"]),
        sentenceCount: muniAnalyseIntValue(from: metadata["sentence_count"]),
        paragraphCount: muniAnalyseIntValue(from: metadata["paragraph_count"]),
        sourceCount: muniAnalyseIntValue(from: metadata["source_count"]),
        documentsExtracted: muniAnalyseIntValue(from: metadata["documents_extracted"]),
        warningCount: muniAnalyseIntValue(from: metadata["warning_count"]),
        mode: muniAnalyseStringValue(from: metadata["mode"]),
        documentMetadataOutputPath: outputPath,
        preview: muniAnalyseStringValue(from: metadata["preview"]),
        topTerms: Array(topTerms),
        documents: documents,
        warnings: warnings
    )
}

private func loadMuniAnalyseResultWarnings(from rawValue: Any?) -> [UIMuniAnalyseResultWarning] {
    (rawValue as? [Any] ?? []).prefix(8).compactMap { item in
        if let message = muniAnalyseStringValue(from: item) {
            return UIMuniAnalyseResultWarning(code: "-", message: message, source_file: "-")
        }
        guard let object = item as? [String: Any] else {
            return nil
        }
        return UIMuniAnalyseResultWarning(
            code: muniAnalyseStringValue(from: object["code"]) ?? "-",
            message: muniAnalyseStringValue(from: object["message"]) ?? "Point à revoir non détaillé.",
            source_file: muniAnalyseStringValue(from: object["source_file"]) ?? "-"
        )
    }
}

private func loadMuniAnalyseDocumentItems(atPath path: String?, logger: Logger) -> [UIMuniAnalyseDocumentItem] {
    guard let path,
          let payload = muniAnalyseReadJSONObject(atPath: path, logger: logger),
          let documents = payload["documents"] as? [[String: Any]] else {
        return []
    }

    return documents.prefix(8).map { item in
        let warnings = item["warnings"] as? [Any] ?? []
        return UIMuniAnalyseDocumentItem(
            source_file: muniAnalyseStringValue(from: item["source_file"]) ?? "-",
            document_type: muniAnalyseStringValue(from: item["document_type"]) ?? "-",
            document_subject: muniAnalyseStringValue(from: item["document_subject"]) ?? "-",
            document_date: muniAnalyseStringValue(from: item["document_date"]) ?? "-",
            provenance: muniAnalyseProvenanceLabel(muniAnalyseStringValue(from: item["extraction_provenance"])),
            warning_count: String(warnings.count)
        )
    }
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
    switch nonEmptyMuniAnalyseValue(rawValue)?.lowercased() {
    case "file":
        return "file"
    case "documents":
        return "documents"
    default:
        return "text"
    }
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

private func muniAnalyseDisplayedSourceKind(_ metadata: MuniAnalyseResultMetadata?) -> String {
    guard let metadata else {
        return "-"
    }
    if metadata.mode == "extract_document_metadata" {
        return "Documents / dossier"
    }
    return muniAnalyseSourceKindLabel(metadata.sourceKind)
}

private func muniAnalyseModeLabel(_ mode: String?) -> String {
    switch mode {
    case "extract_document_metadata":
        return "Métadonnées documentaires"
    default:
        return "Analyse texte"
    }
}

private func muniAnalyseProvenanceLabel(_ provenance: String?) -> String {
    switch provenance {
    case "pdf_text":
        return "Texte PDF"
    case "filename_fallback":
        return "Nom de fichier"
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
    case "Document metadata extraction completed successfully.":
        return "Métadonnées documentaires extraites avec succès."
    case "Document metadata extraction completed with review warnings.":
        return "Métadonnées documentaires extraites avec points à revoir."
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
