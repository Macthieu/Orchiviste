import Foundation
import Fluent
import OrchivisteAnalyseCore
import OrchivisteSharedKit
import Vapor

private struct LocalRouteResult {
    let destinationPath: String
    let fileName: String
    let warnings: [String]
    let pdfStrategy: String?
    let requiresReview: Bool
    let namingRuleID: String?
}

struct ReviewStagingResult {
    let destinationPath: String
    let destinationFolder: String
    let fileName: String
}

func registerRoutingRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("route", ":file_id", use: handleRouteRequest)
    }
}

private func handleRouteRequest(req: Request) async throws -> RoutingResponse {
    guard let fileId = req.parameters.get("file_id") else {
        throw Abort(.badRequest, reason: "file_id est requis.")
    }
    let routeRequest = try? req.content.decode(RoutingRequest.self)
    return try await executeRouting(
        fileId: fileId,
        routeRequest: routeRequest,
        req: req,
        application: req.application,
        database: req.db,
        logger: req.logger
    )
}

func autoRouteIfRequested(
    job: JobRecord,
    application: Application,
    database: Database,
    logger: Logger
) async throws -> RoutingResponse? {
    let requested = job.analysisChamps?["route.auto_requested"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard requested == "true" || requested == "1" else {
        return nil
    }
    guard job.steps.routed == nil else {
        return nil
    }
    return try await executeRouting(
        fileId: job.id.uuidString,
        routeRequest: nil,
        req: nil,
        application: application,
        database: database,
        logger: logger
    )
}

private func executeRouting(
    fileId: String,
    routeRequest: RoutingRequest?,
    req: Request?,
    application: Application,
    database: Database,
    logger: Logger
) async throws -> RoutingResponse {
    guard let routing = ConfigLoader.loadRoutingMap() else {
        throw Abort(.notFound, reason: "Table de routage introuvable.")
    }
    let localSettings = ConfigLoader.loadRoutingLocalSettings()
    let routingRules = ConfigLoader.loadRoutingRules()
    let presets = ConfigLoader.loadPresets()
    let namingRules = ConfigLoader.loadNamingRules()
    let namingThesaurus = ConfigLoader.loadNamingThesauri().first

    var suggestedCode: String?
    var resolvedJobID: UUID?
    var resolvedJob: JobRecord?
    if let jobId = UUID(uuidString: fileId) {
        let inMemory = await application.appState.job(id: jobId)
        let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: database)
        if let job = inMemory ?? persisted {
            await application.appState.cacheJob(job)
            if job.status == .needs_review {
                throw Abort(.conflict, reason: "La tâche exige une revue humaine avant le routage.")
            }
            if job.status == .pending || job.status == .running {
                throw Abort(.conflict, reason: "L'analyse de la tâche n'est pas terminée.")
            }
            suggestedCode = job.suggestedClassCode
            resolvedJobID = jobId
            resolvedJob = job
        }
    }

    var analysis: AnalysisResponse?
    if let resolvedJobID {
        analysis = await application.appState.analysis(jobId: resolvedJobID)
    }
    if analysis == nil, let resolvedJob {
        analysis = makeAnalysisSnapshot(from: resolvedJob, classCodeFallback: resolvedJob.suggestedClassCode)
    }

    let effectiveLocalSettings = mergedLocalRoutingSettings(
        base: localSettings,
        requestedRoot: nonEmpty(resolvedJob?.analysisChamps?["route.requested_output_root"])
    )

    let provisionalRule = selectRoutingRule(
        rules: routingRules?.rules ?? [],
        classCode: nonEmpty(routeRequest?.class_code) ?? suggestedCode,
        analysis: analysis
    )

    let provisionalPreset = presets.first { $0.id == nonEmpty(routeRequest?.preset_id) }
        ?? presets.first { $0.id == nonEmpty(provisionalRule?.preset_id) }
        ?? presets.first { $0.id == resolvedJob?.suggestedPreset }
        ?? presets.first

    let requestedClassCode = nonEmpty(routeRequest?.class_code)
    let ruleClassCode = nonEmpty(provisionalRule?.class_code)
    let ruleWhenClassCode = nonEmpty(provisionalRule?.when_class_code)
    let suggestedClassCode = nonEmpty(suggestedCode)
    let presetClassCode = nonEmpty(provisionalPreset?.class_code)
    let fallbackClassCode = routing.mappings.keys.first
    let classCode = requestedClassCode
        ?? ruleClassCode
        ?? ruleWhenClassCode
        ?? suggestedClassCode
        ?? presetClassCode
        ?? fallbackClassCode
        ?? "UNCLASSIFIED"

    let selectedRule = selectRoutingRule(
        rules: routingRules?.rules ?? [],
        classCode: classCode,
        analysis: analysis
    ) ?? provisionalRule

    let selectedPreset = presets.first { $0.id == nonEmpty(routeRequest?.preset_id) }
        ?? presets.first { $0.id == nonEmpty(selectedRule?.preset_id) }
        ?? provisionalPreset

    let selectedRuleClassCode = nonEmpty(selectedRule?.class_code)
    let selectedRuleWhenClassCode = nonEmpty(selectedRule?.when_class_code)
    let effectiveClassCode = requestedClassCode
        ?? selectedRuleClassCode
        ?? selectedRuleWhenClassCode
        ?? classCode

    guard let target = routing.mappings[effectiveClassCode] ?? routing.mappings.values.first else {
        throw Abort(.notFound, reason: "Aucune cible de routage pour ce code de classement.")
    }

    let folderTemplate = nonEmpty(routeRequest?.destination_folder)
        ?? nonEmpty(selectedRule?.destination_template)
        ?? nonEmpty(effectiveLocalSettings?.default_destination_template)
        ?? target.folder_expr
    let resolved = resolveFolderTemplate(
        template: folderTemplate,
        classCode: effectiveClassCode,
        analysis: analysis,
        presetID: selectedPreset?.id
    )

    var resolvedFileName: String?
    var routeNamingRuleID: String?
    if let resolvedJob {
        let effectiveNameFormat = nonEmpty(routeRequest?.name_format)
            ?? nonEmpty(selectedRule?.name_format)
            ?? nonEmpty(selectedPreset?.name_format)
            ?? nonEmpty(effectiveLocalSettings?.default_name_format)
        let resolvedNaming = resolvedRoutingFileName(
            job: resolvedJob,
            classCode: effectiveClassCode,
            analysis: analysis,
            preset: selectedPreset,
            explicitPreferredFileName: nil,
            legacyNameFormat: effectiveNameFormat,
            requestedExportType: routeRequest?.export_type,
            namingRule: selectNamingRuleForRouting(
                job: resolvedJob,
                analysis: analysis,
                preset: selectedPreset,
                rules: namingRules
            ),
            namingThesaurus: namingThesaurus
        )
        resolvedFileName = resolvedNaming.fileName
        routeNamingRuleID = resolvedNaming.namingRuleID
    }

    var routeMode = "stub"
    var destinationURL: String?
    var movedItemID: String?
    var destinationLocalPath: String?
    var destinationFolderDisplay: String?
    var routePDFStrategy: String?
    var routeOCRState = "n/a"

    if let resolvedJob {
        do {
            if let req,
               let graphRoute = try await SharePointGraphRouter.routeIfEnabled(
                job: resolvedJob,
                target: target,
                resolvedFolder: resolved,
                classCode: effectiveClassCode,
                preferredFileName: resolvedFileName,
                req: req
            ) {
                routeMode = "graph"
                destinationURL = graphRoute.destinationURL
                movedItemID = graphRoute.movedItemID
                resolvedFileName = graphRoute.fileName
                destinationFolderDisplay = routeDestinationFolderDisplay(
                    mode: routeMode,
                    target: target,
                    resolvedFolder: resolved,
                    destinationLocalPath: nil
                )
                await EventPublisher.publish(
                    type: "route.graph_applied",
                    payload: [
                        "job_id": resolvedJob.id.uuidString,
                        "class_code": effectiveClassCode,
                        "mode": routeMode,
                        "file_name": graphRoute.fileName
                    ],
                    application: application,
                    database: database,
                    logger: logger
                )
                for warning in graphRoute.warnings {
                    await EventPublisher.publish(
                        type: "route.warning",
                        payload: [
                            "job_id": resolvedJob.id.uuidString,
                            "warning": warning,
                            "mode": routeMode
                        ],
                        application: application,
                        database: database,
                        logger: logger
                    )
                }
                if graphRoute.requiresReview,
                   let flagged = await application.appState.flagNeedsReview(
                    jobId: resolvedJob.id,
                    reason: "graph_cleanup_needs_review"
                   ) {
                    try await JobPersistenceRepository.upsert(job: flagged, on: database)
                    await EventPublisher.publish(
                        type: "job.needs_review",
                        payload: [
                            "job_id": resolvedJob.id.uuidString,
                            "reason": "graph_cleanup_needs_review"
                        ],
                        application: application,
                        database: database,
                        logger: logger
                    )
                }
            } else if let localRoute = try routeLocalFileIfPossible(
                job: resolvedJob,
                resolvedFolder: resolved,
                classCode: effectiveClassCode,
                localSettings: effectiveLocalSettings,
                preferredFileName: resolvedFileName,
                preset: selectedPreset,
                requestedExportType: routeRequest?.export_type,
                analysis: analysis,
                namingRule: selectNamingRuleForRouting(
                    job: resolvedJob,
                    analysis: analysis,
                    preset: selectedPreset,
                    rules: namingRules
                ),
                namingThesaurus: namingThesaurus,
                logger: logger
            ) {
                routeMode = "local"
                destinationLocalPath = localRoute.destinationPath
                resolvedFileName = localRoute.fileName
                routeNamingRuleID = localRoute.namingRuleID
                destinationFolderDisplay = routeDestinationFolderDisplay(
                    mode: routeMode,
                    target: target,
                    resolvedFolder: resolved,
                    destinationLocalPath: localRoute.destinationPath
                )
                routePDFStrategy = localRoute.pdfStrategy
                routeOCRState = routeOCRStatus(for: localRoute.pdfStrategy)
                await EventPublisher.publish(
                    type: "route.local_applied",
                    payload: [
                        "job_id": resolvedJob.id.uuidString,
                        "class_code": effectiveClassCode,
                        "mode": routeMode,
                        "file_name": localRoute.fileName,
                        "destination_path": localRoute.destinationPath
                    ],
                    application: application,
                    database: database,
                    logger: logger
                )
                for warning in localRoute.warnings {
                    await EventPublisher.publish(
                        type: "route.warning",
                        payload: [
                            "job_id": resolvedJob.id.uuidString,
                            "warning": warning,
                            "mode": routeMode
                        ],
                        application: application,
                        database: database,
                        logger: logger
                    )
                }
                if let pdfStrategy = localRoute.pdfStrategy {
                    await EventPublisher.publish(
                        type: "route.pdf_export_applied",
                        payload: [
                            "job_id": resolvedJob.id.uuidString,
                            "strategy": pdfStrategy,
                            "mode": routeMode
                        ],
                        application: application,
                        database: database,
                        logger: logger
                    )
                }
                if localRoute.requiresReview,
                   let flagged = await application.appState.flagNeedsReview(
                    jobId: resolvedJob.id,
                    reason: "pdfa_fallback_needs_review"
                   ) {
                    try await JobPersistenceRepository.upsert(job: flagged, on: database)
                    await EventPublisher.publish(
                        type: "job.needs_review",
                        payload: [
                            "job_id": resolvedJob.id.uuidString,
                            "reason": "pdfa_fallback_needs_review"
                        ],
                        application: application,
                        database: database,
                        logger: logger
                    )
                }
            }
        } catch {
            await EventPublisher.publish(
                type: "route.failed",
                payload: [
                    "job_id": resolvedJob.id.uuidString,
                    "class_code": effectiveClassCode
                ],
                application: application,
                database: database,
                logger: logger
            )
            throw error
        }
    }

    if let resolvedJobID,
       let updatedJob = await application.appState.markRouted(
        jobId: resolvedJobID,
        classCode: effectiveClassCode,
        details: buildRouteJobDetails(
            mode: routeMode,
            target: target,
            resolvedFolder: resolved,
            resolvedFileName: resolvedFileName,
            destinationURL: destinationURL,
            destinationLocalPath: destinationLocalPath,
            destinationFolderDisplay: destinationFolderDisplay,
            pdfStrategy: routePDFStrategy,
            ocrStatus: routeOCRState,
            namingRuleID: routeNamingRuleID
        )
       ) {
        try await JobPersistenceRepository.upsert(job: updatedJob, on: database)
        await EventPublisher.publish(
            type: "job.routed",
            payload: [
                "job_id": resolvedJobID.uuidString,
                "class_code": effectiveClassCode,
                "mode": routeMode
            ],
            application: application,
            database: database,
            logger: logger
        )
    } else {
        await EventPublisher.publish(
            type: "route.ready",
            payload: [
                "file_id": fileId,
                "class_code": effectiveClassCode,
                "mode": routeMode
            ],
            application: application,
            database: database,
            logger: logger
        )
    }

    return RoutingResponse(
        file_id: fileId,
        class_code: effectiveClassCode,
        target: target,
        resolved_folder: resolved,
        mode: routeMode,
        destination_url: destinationURL,
        moved_item_id: movedItemID,
        destination_local_path: destinationLocalPath,
        resolved_file_name: resolvedFileName
    )
}

private func buildRouteJobDetails(
    mode: String,
    target: RoutingTarget,
    resolvedFolder: String,
    resolvedFileName: String?,
    destinationURL: String?,
    destinationLocalPath: String?,
    destinationFolderDisplay: String?,
    pdfStrategy: String?,
    ocrStatus: String,
    namingRuleID: String?
) -> [String: String] {
    var details: [String: String] = [:]
    details["route.mode"] = mode
    if !resolvedFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        details["route.resolved_folder"] = resolvedFolder
    }
    if let resolvedFileName, !resolvedFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        details["route.resolved_file_name"] = resolvedFileName
    }
    if let destinationURL, !destinationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        details["route.destination_url"] = destinationURL
    }
    if let destinationLocalPath, !destinationLocalPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        details["route.destination_local_path"] = destinationLocalPath
    }
    if let destinationFolderDisplay, !destinationFolderDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        details["route.destination_folder_display"] = destinationFolderDisplay
    }
    if let pdfStrategy, !pdfStrategy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        details["route.pdf_strategy"] = pdfStrategy
    }
    if let namingRuleID, !namingRuleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        details["route.naming_rule_id"] = namingRuleID
    }
    details["route.ocr_status"] = ocrStatus
    details["route.metadata_status"] = routeMetadataStatus(for: target)
    return details
}

func buildReviewStagingJobDetails(_ staging: ReviewStagingResult) -> [String: String] {
    [
        "route.review_staging_status": "staged",
        "route.review_staging_path": staging.destinationPath,
        "route.review_staging_folder": staging.destinationFolder,
        "route.review_staging_file_name": staging.fileName
    ]
}

private func routeDestinationFolderDisplay(
    mode: String,
    target: RoutingTarget,
    resolvedFolder: String,
    destinationLocalPath: String?
) -> String {
    if mode == "local",
       let destinationLocalPath,
       !destinationLocalPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: destinationLocalPath).deletingLastPathComponent().path
    }

    if mode == "graph" {
        let segments = [target.site, target.library, resolvedFolder]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return segments.isEmpty ? "-" : segments.joined(separator: " / ")
    }

    return "-"
}

private func routeMetadataStatus(for target: RoutingTarget) -> String {
    let metadata = target.metadata ?? [:]
    return metadata.isEmpty ? "n/a" : "pending"
}

func stageReviewFileIfNeeded(
    job: JobRecord,
    localSettings: RoutingLocalSettings?,
    logger: Logger
) throws -> ReviewStagingResult? {
    guard job.source.kind.lowercased() == "local" else {
        return nil
    }

    if let existingPath = nonEmpty(job.analysisChamps?["route.review_staging_path"]),
       let existingFolder = nonEmpty(job.analysisChamps?["route.review_staging_folder"]),
       let existingName = nonEmpty(job.analysisChamps?["route.review_staging_file_name"]),
       FileManager.default.fileExists(atPath: existingPath) {
        return ReviewStagingResult(
            destinationPath: existingPath,
            destinationFolder: existingFolder,
            fileName: existingName
        )
    }

    guard let sourceURL = resolveLocalFileURL(raw: job.fileURL) else {
        logger.warning("Quarantaine revue ignorée: chemin source non valide.", metadata: [
            "job_id": .string(job.id.uuidString)
        ])
        return nil
    }
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        logger.warning("Quarantaine revue ignorée: fichier source introuvable.", metadata: [
            "job_id": .string(job.id.uuidString),
            "path": .string(sourceURL.path)
        ])
        return nil
    }

    let reviewDate = formatDate(Date(), pattern: "yyyy-MM-dd")
    let reviewRoot = localRoutingRootDirectory(settings: localSettings)
        .appendingPathComponent("A_reviser", isDirectory: true)
        .appendingPathComponent(reviewDate, isDirectory: true)
    try FileManager.default.createDirectory(
        at: reviewRoot,
        withIntermediateDirectories: true,
        attributes: nil
    )

    let destinationURL = uniqueDestinationURL(
        in: reviewRoot,
        proposedFileName: sourceURL.lastPathComponent
    )
    do {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    } catch {
        throw Abort(
            .internalServerError,
            reason: "Échec de la copie en quarantaine de revue: \(error.localizedDescription)"
        )
    }

    return ReviewStagingResult(
        destinationPath: destinationURL.path,
        destinationFolder: reviewRoot.path,
        fileName: destinationURL.lastPathComponent
    )
}

private func routeOCRStatus(for pdfStrategy: String?) -> String {
    guard let pdfStrategy else {
        return "n/a"
    }
    return pdfStrategy.contains("searchable") ? "ok" : "n/a"
}

private func routeLocalFileIfPossible(
    job: JobRecord,
    resolvedFolder: String,
    classCode: String,
    localSettings: RoutingLocalSettings?,
    preferredFileName: String?,
    preset: Preset?,
    requestedExportType: String?,
    analysis: AnalysisResponse?,
    namingRule: NamingRuleDefinition?,
    namingThesaurus: NamingThesaurus?,
    logger: Logger
) throws -> LocalRouteResult? {
    guard job.source.kind.lowercased() == "local" else {
        return nil
    }

    guard let sourceURL = resolveLocalFileURL(raw: job.fileURL) else {
        logger.warning("Routage local ignoré: chemin source non valide.", metadata: [
            "job_id": .string(job.id.uuidString)
        ])
        return nil
    }

    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        logger.warning("Routage local ignoré: fichier source introuvable.", metadata: [
            "job_id": .string(job.id.uuidString),
            "path": .string(sourceURL.path)
        ])
        return nil
    }

    let rootDirectory = localRoutingRootDirectory(settings: localSettings)
    let safeResolvedFolder = sanitizeRelativeFolder(resolvedFolder)
    let destinationDirectory: URL
    if safeResolvedFolder.isEmpty {
        destinationDirectory = rootDirectory
    } else {
        destinationDirectory = rootDirectory.appendingPathComponent(safeResolvedFolder, isDirectory: true)
    }
    try FileManager.default.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true,
        attributes: nil
    )

    let routedNaming = resolvedRoutingFileName(
        job: job,
        classCode: classCode,
        analysis: analysis,
        preset: preset,
        explicitPreferredFileName: preferredFileName,
        legacyNameFormat: nil,
        requestedExportType: requestedExportType,
        namingRule: namingRule,
        namingThesaurus: namingThesaurus
    )
    let destinationName = routedNaming.fileName ?? routedLocalFileName(
        classCode: classCode,
        originalName: sourceURL.lastPathComponent
    )
    let shouldAttemptPDFA = ArchivalPDFExporter.shouldAttemptPDFA(
        preset: preset,
        requestedExportType: requestedExportType
    )
    let shouldConvertOfficeToPDF = shouldAttemptPDFA && ["docx", "xlsx", "pptx"].contains(sourceURL.pathExtension.lowercased())
    let effectiveDestinationName = shouldConvertOfficeToPDF
        ? replaceFileExtension(destinationName, with: "pdf")
        : destinationName
    let destinationURL = uniqueDestinationURL(
        in: destinationDirectory,
        proposedFileName: effectiveDestinationName
    )

    if sourceURL.pathExtension.lowercased() == "pdf" {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-route-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let searchableURL = tempDirectory.appendingPathComponent("searchable.pdf")
        let builtSearchable = (try? SearchablePDFBuilder.buildIfNeeded(
            sourceURL: sourceURL,
            destinationURL: searchableURL,
            logger: logger
        )) == true
        let candidateURL = builtSearchable ? searchableURL : sourceURL

        let pdfaDestination = tempDirectory.appendingPathComponent("archive.pdf")
        let pdfaResult = ArchivalPDFExporter.convertIfNeeded(
            sourceURL: candidateURL,
            destinationURL: pdfaDestination,
            preset: preset,
            requestedExportType: requestedExportType,
            logger: logger
        )
        let finalSourceURL = pdfaResult.converted ? pdfaDestination : candidateURL
        _ = try moveOrCopyLocalRouteFile(
            sourceURL: finalSourceURL,
            destinationURL: destinationURL
        )

        if finalSourceURL != sourceURL {
            do {
                try FileManager.default.removeItem(at: sourceURL)
            } catch {
                logger.warning("La suppression de la source apres export PDF a echoue.", metadata: [
                    "job_id": .string(job.id.uuidString),
                    "source_path": .string(sourceURL.path),
                    "error": .string(error.localizedDescription)
                ])
            }
        }

        let strategy: String?
        if pdfaResult.converted {
            strategy = builtSearchable ? "searchable+pdfa" : "pdfa"
        } else if builtSearchable {
            strategy = "searchable"
        } else {
            strategy = nil
        }

        return LocalRouteResult(
            destinationPath: destinationURL.path,
            fileName: destinationURL.lastPathComponent,
            warnings: pdfaResult.warnings,
            pdfStrategy: strategy,
            requiresReview: pdfaWarningsRequireReview(pdfaResult.warnings),
            namingRuleID: routedNaming.namingRuleID
        )
    }

    if shouldConvertOfficeToPDF,
       let extracted = DocumentTextExtractor.extract(fileURL: sourceURL, logger: logger),
       let previewPDFURL = extracted.previewPDFURL {
        defer {
            for artifact in extracted.temporaryArtifacts {
                try? FileManager.default.removeItem(at: artifact)
            }
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-route-office-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let pdfaDestination = tempDirectory.appendingPathComponent("archive.pdf")
        let pdfaResult = ArchivalPDFExporter.convertIfNeeded(
            sourceURL: previewPDFURL,
            destinationURL: pdfaDestination,
            preset: preset,
            requestedExportType: requestedExportType,
            logger: logger
        )
        let finalSourceURL = pdfaResult.converted ? pdfaDestination : previewPDFURL
        _ = try moveOrCopyLocalRouteFile(
            sourceURL: finalSourceURL,
            destinationURL: destinationURL
        )

        do {
            try FileManager.default.removeItem(at: sourceURL)
        } catch {
            logger.warning("La suppression de la source apres conversion Office -> PDF a echoue.", metadata: [
                "job_id": .string(job.id.uuidString),
                "source_path": .string(sourceURL.path),
                "error": .string(error.localizedDescription)
            ])
        }

        let strategy = pdfaResult.converted ? "office+pdfa" : "office+pdf"
        return LocalRouteResult(
            destinationPath: destinationURL.path,
            fileName: destinationURL.lastPathComponent,
            warnings: extracted.warnings + pdfaResult.warnings,
            pdfStrategy: strategy,
            requiresReview: pdfaWarningsRequireReview(pdfaResult.warnings),
            namingRuleID: routedNaming.namingRuleID
        )
    }

    _ = try moveOrCopyLocalRouteFile(sourceURL: sourceURL, destinationURL: destinationURL)
    return LocalRouteResult(
        destinationPath: destinationURL.path,
        fileName: destinationURL.lastPathComponent,
        warnings: [],
        pdfStrategy: nil,
        requiresReview: false,
        namingRuleID: routedNaming.namingRuleID
    )
}

private func moveOrCopyLocalRouteFile(
    sourceURL: URL,
    destinationURL: URL
) throws -> Bool {
    do {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        return false
    } catch {
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            if sourceURL != destinationURL {
                try? FileManager.default.removeItem(at: sourceURL)
            }
            return true
        } catch {
            throw Abort(
                .internalServerError,
                reason: "Échec du routage local du fichier: \(error.localizedDescription)"
            )
        }
    }
}

private func resolveLocalFileURL(raw: String) -> URL? {
    if let parsed = URL(string: raw), parsed.isFileURL {
        return parsed
    }
    if raw.hasPrefix("/") {
        return URL(fileURLWithPath: raw)
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return cwd.appendingPathComponent(raw)
}

func mergedLocalRoutingSettings(
    base: RoutingLocalSettings?,
    requestedRoot: String?
) -> RoutingLocalSettings? {
    guard let requestedRoot = nonEmpty(requestedRoot) else {
        return base
    }
    return RoutingLocalSettings(
        local_route_root: requestedRoot,
        default_destination_template: base?.default_destination_template,
        default_name_format: base?.default_name_format
    )
}

private func localRoutingRootDirectory(settings: RoutingLocalSettings?) -> URL {
    if let configured = nonEmpty(settings?.local_route_root) {
        if configured.hasPrefix("/") {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(configured, isDirectory: true)
    }

    if let configured = Environment.get("ORCHIVISTE_LOCAL_ROUTE_ROOT")?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !configured.isEmpty {
        return URL(fileURLWithPath: configured, isDirectory: true)
    }

    if let sqlitePath = Environment.get("ORCHIVISTE_SQLITE_PATH"),
       sqlitePath.hasPrefix("/") {
        return URL(fileURLWithPath: sqlitePath)
            .deletingLastPathComponent()
            .appendingPathComponent("routed", isDirectory: true)
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".orchiviste-routed", isDirectory: true)
}

private func sanitizeRelativeFolder(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        .joined(separator: "/")
}

private func routedLocalFileName(classCode: String, originalName: String) -> String {
    let ext = URL(fileURLWithPath: originalName).pathExtension
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let stamp = formatter.string(from: Date())
    if ext.isEmpty {
        return "\(classCode)-\(stamp)"
    }
    return "\(classCode)-\(stamp).\(ext)"
}

private func resolveFolderTemplate(
    template: String,
    classCode: String,
    analysis: AnalysisResponse?,
    presetID: String?
) -> String {
    let year = String(Calendar.current.component(.year, from: Date()))
    let primarySujet = sanitizeFolderToken(analysis?.sujets.first ?? "general")
    let sujets = sanitizeFolderToken((analysis?.sujets ?? ["general"]).joined(separator: "-"))
    let typeDoc = sanitizeFolderToken(analysis?.type_doc ?? "autre")
    let preset = sanitizeFolderToken(presetID ?? "preset_default")

    let values: [String: String] = [
        "code": sanitizeFolderToken(classCode),
        "class_code": sanitizeFolderToken(classCode),
        "year": sanitizeFolderToken(year),
        "type": typeDoc,
        "type_doc": typeDoc,
        "sujet": primarySujet,
        "sujets": sujets,
        "preset": preset,
        "preset_id": preset
    ]
    let resolved = substituteTokens(in: template, values: values)
    return sanitizeRelativeFolder(resolved)
}

private func buildRoutedFileName(
    classCode: String,
    originalName: String,
    analysis: AnalysisResponse?,
    presetID: String?,
    jobID: String,
    nameFormat: String?,
    postprocess: [String]
) -> String {
    let originalURL = URL(fileURLWithPath: originalName)
    let originalStem = originalURL.deletingPathExtension().lastPathComponent
    let ext = originalURL.pathExtension

    let now = Date()
    let dateStamp = nonEmpty(analysis?.champs["date"]) ?? formatDate(now, pattern: "yyyy-MM-dd")
    let dateTimeStamp = formatDate(now, pattern: "yyyyMMdd-HHmmss")
    let number = nonEmpty(analysis?.champs["numero"]) ?? ""
    let committee = nonEmpty(analysis?.champs["comite"]) ?? ""
    let typeDoc = nonEmpty(analysis?.type_doc) ?? "Document"
    let sujet = nonEmpty(analysis?.sujets.first) ?? originalStem
    let sujets = ((analysis?.sujets ?? []).compactMap(nonEmpty).isEmpty ? [sujet] : (analysis?.sujets ?? [sujet])).joined(separator: "-")

    let values: [String: String] = [
        "class_code": classCode,
        "code": classCode,
        "type": typeDoc,
        "type_doc": typeDoc,
        "sujet": sujet,
        "sujets": sujets,
        "numero": number,
        "comite": committee,
        "date": dateStamp,
        "datetime": dateTimeStamp,
        "preset": presetID ?? "preset_default",
        "preset_id": presetID ?? "preset_default",
        "job_id": jobID,
        "original": originalStem
    ]

    let format = nonEmpty(nameFormat) ?? "{class_code}-{type_doc}-{sujet}-{date}-{numero}"
    var rawName = substituteTokens(in: format, values: values)
    rawName = applyPostprocess(rawName, steps: postprocess)
    rawName = rawName.replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
    rawName = rawName.replacingOccurrences(of: #"\s+-"#, with: "-", options: .regularExpression)
    rawName = rawName.replacingOccurrences(of: #"-\s+"#, with: "-", options: .regularExpression)
    rawName = NamingPolicy.normalizedStem(rawName)
    rawName = sanitizeFileName(rawName)
    if rawName.isEmpty {
        rawName = NamingPolicy.normalizedStem(originalStem)
    }
    if rawName.isEmpty {
        rawName = "\(classCode)-\(dateTimeStamp)"
    }
    let baseName = rawName.lowercased().hasSuffix(".\(ext.lowercased())") || ext.isEmpty
        ? rawName
        : "\(rawName).\(ext)"
    return NamingPolicy.truncateFileNameIfNeeded(baseName)
}

private struct ResolvedRoutingNaming {
    let fileName: String?
    let namingRuleID: String?
}

struct RoutePreview {
    let fileName: String?
    let destinationFolderDisplay: String?
    let namingRuleID: String?
    let namingSource: String
}

func buildRoutePreview(
    job: JobRecord,
    analysis: AnalysisResponse?,
    requestedClassCode: String? = nil,
    requestedPresetID: String? = nil,
    requestedDestinationFolder: String? = nil,
    requestedNameFormat: String? = nil,
    requestedExportType: String? = nil
) -> RoutePreview? {
    guard let routing = ConfigLoader.loadRoutingMap() else {
        return nil
    }

    let localSettings = ConfigLoader.loadRoutingLocalSettings()
    let routingRules = ConfigLoader.loadRoutingRules()
    let presets = ConfigLoader.loadPresets()
    let namingRules = ConfigLoader.loadNamingRules()
    let namingThesaurus = ConfigLoader.loadNamingThesauri().first
    let effectiveAnalysis = analysis ?? makeAnalysisSnapshot(from: job, classCodeFallback: job.suggestedClassCode)
    let effectiveLocalSettings = mergedLocalRoutingSettings(
        base: localSettings,
        requestedRoot: nonEmpty(job.analysisChamps?["route.requested_output_root"])
    )

    let provisionalRule = selectRoutingRule(
        rules: routingRules?.rules ?? [],
        classCode: nonEmpty(requestedClassCode) ?? nonEmpty(job.suggestedClassCode),
        analysis: effectiveAnalysis
    )
    let provisionalPreset = presets.first { $0.id == nonEmpty(requestedPresetID) }
        ?? presets.first { $0.id == nonEmpty(provisionalRule?.preset_id) }
        ?? presets.first { $0.id == job.suggestedPreset }
        ?? presets.first

    let classCode = nonEmpty(requestedClassCode)
        ?? nonEmpty(provisionalRule?.class_code)
        ?? nonEmpty(provisionalRule?.when_class_code)
        ?? nonEmpty(job.suggestedClassCode)
        ?? nonEmpty(provisionalPreset?.class_code)
        ?? routing.mappings.keys.first
        ?? "UNCLASSIFIED"

    let selectedRule = selectRoutingRule(
        rules: routingRules?.rules ?? [],
        classCode: classCode,
        analysis: effectiveAnalysis
    ) ?? provisionalRule
    let selectedPreset = presets.first { $0.id == nonEmpty(requestedPresetID) }
        ?? presets.first { $0.id == nonEmpty(selectedRule?.preset_id) }
        ?? provisionalPreset

    let effectiveClassCode = nonEmpty(requestedClassCode)
        ?? nonEmpty(selectedRule?.class_code)
        ?? nonEmpty(selectedRule?.when_class_code)
        ?? classCode

    guard let target = routing.mappings[effectiveClassCode] ?? routing.mappings.values.first else {
        return nil
    }

    let folderTemplate = nonEmpty(requestedDestinationFolder)
        ?? nonEmpty(selectedRule?.destination_template)
        ?? nonEmpty(effectiveLocalSettings?.default_destination_template)
        ?? target.folder_expr
    let resolvedFolder = resolveFolderTemplate(
        template: folderTemplate,
        classCode: effectiveClassCode,
        analysis: effectiveAnalysis,
        presetID: selectedPreset?.id
    )
    let effectiveNameFormat = nonEmpty(requestedNameFormat)
        ?? nonEmpty(selectedRule?.name_format)
        ?? nonEmpty(selectedPreset?.name_format)
        ?? nonEmpty(effectiveLocalSettings?.default_name_format)
    let selectedNamingRule = selectNamingRuleForRouting(
        job: job,
        analysis: effectiveAnalysis,
        preset: selectedPreset,
        rules: namingRules
    )
    let resolvedNaming = resolvedRoutingFileName(
        job: job,
        classCode: effectiveClassCode,
        analysis: effectiveAnalysis,
        preset: selectedPreset,
        explicitPreferredFileName: nil,
        legacyNameFormat: effectiveNameFormat,
        requestedExportType: requestedExportType,
        namingRule: selectedNamingRule,
        namingThesaurus: namingThesaurus
    )

    let destinationFolderDisplay: String?
    if job.source.kind.lowercased() == "local" {
        let localRoot = localRoutingRootDirectory(settings: effectiveLocalSettings)
        let safeResolvedFolder = sanitizeRelativeFolder(resolvedFolder)
        let destinationLocalPath = safeResolvedFolder.isEmpty
            ? localRoot.path
            : localRoot.appendingPathComponent(safeResolvedFolder, isDirectory: true).path
        destinationFolderDisplay = routeDestinationFolderDisplay(
            mode: "local",
            target: target,
            resolvedFolder: resolvedFolder,
            destinationLocalPath: destinationLocalPath
        )
    } else {
        destinationFolderDisplay = routeDestinationFolderDisplay(
            mode: "graph",
            target: target,
            resolvedFolder: resolvedFolder,
            destinationLocalPath: nil
        )
    }

    let namingSource: String
    if let namingRuleID = resolvedNaming.namingRuleID, !namingRuleID.isEmpty {
        namingSource = "Règle déclarative"
    } else if effectiveNameFormat != nil {
        namingSource = "Format de nom actuel"
    } else {
        namingSource = "Format standard"
    }

    return RoutePreview(
        fileName: resolvedNaming.fileName,
        destinationFolderDisplay: destinationFolderDisplay,
        namingRuleID: resolvedNaming.namingRuleID,
        namingSource: namingSource
    )
}

private func resolvedRoutingFileName(
    job: JobRecord,
    classCode: String,
    analysis: AnalysisResponse?,
    preset: Preset?,
    explicitPreferredFileName: String?,
    legacyNameFormat: String?,
    requestedExportType: String?,
    namingRule: NamingRuleDefinition?,
    namingThesaurus: NamingThesaurus?
) -> ResolvedRoutingNaming {
    guard let sourceURL = resolveLocalFileURL(raw: job.fileURL) else {
        return ResolvedRoutingNaming(fileName: explicitPreferredFileName, namingRuleID: nil)
    }

    if let explicitPreferredFileName = nonEmpty(explicitPreferredFileName) {
        return ResolvedRoutingNaming(fileName: explicitPreferredFileName, namingRuleID: nil)
    }

    let effectiveNameFormat = nonEmpty(legacyNameFormat)
    if effectiveNameFormat == nil,
       let namingRule,
       let rendered = renderFileNameUsingNamingRule(
            job: job,
            sourceURL: sourceURL,
            analysis: analysis,
            preset: preset,
            requestedExportType: requestedExportType,
            namingRule: namingRule,
            namingThesaurus: namingThesaurus
       ) {
        return ResolvedRoutingNaming(fileName: rendered, namingRuleID: namingRule.id)
    }

    let legacyName = buildRoutedFileName(
        classCode: classCode,
        originalName: sourceURL.lastPathComponent,
        analysis: analysis,
        presetID: preset?.id,
        jobID: job.id.uuidString,
        nameFormat: effectiveNameFormat,
        postprocess: preset?.postprocess ?? []
    )
    return ResolvedRoutingNaming(fileName: legacyName, namingRuleID: nil)
}

private func selectNamingRuleForRouting(
    job: JobRecord,
    analysis: AnalysisResponse?,
    preset: Preset?,
    rules: [NamingRuleDefinition]
) -> NamingRuleDefinition? {
    guard !rules.isEmpty else {
        return nil
    }

    let haystack = buildNamingDetectionText(job: job, analysis: analysis, preset: preset)
    let engine = DeclarativeNamingRuleEngine()

    let prioritizedIDs = [
        preset?.id,
        analysis?.suggested_preset,
        analysis?.type_doc,
        job.analysisTypeDoc,
        job.analysisChamps?["metadata.type_document"]
    ]
        .compactMap { nonEmpty($0) }
        .map { normalizeRoutingToken($0) }

    for token in prioritizedIDs {
        if token?.contains("resolution") == true,
           let rule = rules.first(where: { $0.id == "rule_resolution_conseil_municipal" }) {
            return rule
        }
        if token?.contains("contrat") == true || token?.contains("entente") == true || token?.contains("bail") == true,
           let rule = rules.first(where: { $0.id == "rule_entente_uniformisee" }) {
            return rule
        }
    }

    return engine.detectRule(
        in: haystack,
        metadata: NamingSourceMetadata(
            fileName: URL(fileURLWithPath: job.fileURL).lastPathComponent,
            fileExtension: URL(fileURLWithPath: job.fileURL).pathExtension,
            originalName: URL(fileURLWithPath: job.fileURL).lastPathComponent,
            hints: job.analysisChamps
        ),
        rules: rules
    )
}

private func renderFileNameUsingNamingRule(
    job: JobRecord,
    sourceURL: URL,
    analysis: AnalysisResponse?,
    preset: Preset?,
    requestedExportType: String?,
    namingRule: NamingRuleDefinition,
    namingThesaurus: NamingThesaurus?
) -> String? {
    let sourceExtension = sourceURL.pathExtension.lowercased()
    let willProducePDF = sourceExtension == "pdf"
        || ArchivalPDFExporter.shouldAttemptPDFA(preset: preset, requestedExportType: requestedExportType)
    guard willProducePDF else {
        return nil
    }

    let engine = DeclarativeNamingRuleEngine()
    let detectionText = buildNamingDetectionText(job: job, analysis: analysis, preset: preset)
    let metadata = NamingSourceMetadata(
        fileName: sourceURL.lastPathComponent,
        fileExtension: sourceExtension,
        originalName: sourceURL.lastPathComponent,
        hints: job.analysisChamps
    )
    var fields = engine.extractFields(from: detectionText, rule: namingRule, metadata: metadata)
    for (key, value) in overlayNamingFields(job: job, analysis: analysis, sourceURL: sourceURL) {
        if nonEmpty(fields[key]) == nil {
            fields[key] = value
        }
    }

    let normalized = engine.normalizeFields(fields, rule: namingRule, thesaurus: namingThesaurus)
    let rendered = engine.renderFilename(rule: namingRule, fields: normalized)
    let issues = engine.validateFilename(rendered, rule: namingRule, fields: normalized)
    if issues.contains(where: { $0.level == .error }) {
        return nil
    }
    return rendered
}

private func buildNamingDetectionText(
    job: JobRecord,
    analysis: AnalysisResponse?,
    preset: Preset?
) -> String {
    var parts: [String] = [URL(fileURLWithPath: job.fileURL).lastPathComponent]
    if let typeDoc = nonEmpty(analysis?.type_doc) ?? nonEmpty(job.analysisTypeDoc) {
        parts.append(typeDoc)
    }
    if let sujets = analysis?.sujets, !sujets.isEmpty {
        parts.append(sujets.joined(separator: " "))
    } else if let sujets = job.analysisSujets, !sujets.isEmpty {
        parts.append(sujets.joined(separator: " "))
    }
    if let presetName = nonEmpty(preset?.name) {
        parts.append(presetName)
    }
    if let presetDescription = nonEmpty(preset?.description) {
        parts.append(presetDescription)
    }
    if let champs = analysis?.champs ?? job.analysisChamps {
        let usefulKeys = [
            "summary.title",
            "summary.generated",
            "resolution_titre",
            "document_objet",
            "metadata.objet",
            "metadata.type_document",
            "metadata.numero_document",
            "metadata.date_document",
            "cocontractant",
            "periode"
        ]
        for key in usefulKeys {
            if let value = nonEmpty(champs[key]) {
                parts.append(value)
            }
        }
        for value in champs.values where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(value)
        }
    }
    return parts.joined(separator: "\n")
}

private func overlayNamingFields(
    job: JobRecord,
    analysis: AnalysisResponse?,
    sourceURL: URL
) -> [String: String] {
    let champs = analysis?.champs ?? job.analysisChamps ?? [:]
    let date = nonEmpty(champs["date"])
        ?? nonEmpty(champs["metadata.date_document"])
    let numero = nonEmpty(champs["numero"])
        ?? nonEmpty(champs["metadata.numero_document"])
    let title = nonEmpty(champs["resolution_titre"])
        ?? nonEmpty(champs["summary.title"])
        ?? nonEmpty(champs["metadata.objet"])
        ?? nonEmpty(champs["document_objet"])
    let object = nonEmpty(champs["document_objet"])
        ?? nonEmpty(champs["metadata.objet"])
        ?? nonEmpty(champs["summary.title"])
        ?? title
    let counterparty = nonEmpty(champs["cocontractant"])
        ?? nonEmpty(champs["metadata.cocontractant"])
        ?? nonEmpty(champs["organisme_tiers"])
        ?? nonEmpty(champs["metadata.organisme_tiers"])
    let period = nonEmpty(champs["periode"])
        ?? nonEmpty(champs["metadata.periode"])
        ?? date.flatMap { String($0.prefix(4)) }

    var values: [String: String] = [:]
    if let numero { values["numero"] = numero }
    if let date { values["date"] = date }
    if let title { values["titre"] = title }
    if let object { values["objet"] = object }
    if let counterparty { values["cocontractant"] = counterparty }
    if let period { values["periode"] = period }
    values["original"] = sourceURL.deletingPathExtension().lastPathComponent
    return values
}

private func substituteTokens(in raw: String, values: [String: String]) -> String {
    var output = raw
    for (key, value) in values {
        output = output.replacingOccurrences(of: "{\(key)}", with: value)
    }
    return output
}

private func applyPostprocess(_ value: String, steps: [String]) -> String {
    var output = value
    for rawStep in steps {
        switch rawStep.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "upper":
            output = output.uppercased()
        case "lower":
            output = output.lowercased()
        case "trim":
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        case "slug":
            output = slugify(output)
        default:
            continue
        }
    }
    return output
}

private func slugify(_ value: String) -> String {
    let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let replaced = folded.replacingOccurrences(
        of: "[^a-zA-Z0-9._-]+",
        with: "-",
        options: .regularExpression
    )
    return replaced
        .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        .lowercased()
}

private func sanitizeFileName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0000}")
    let components = value.unicodeScalars.map { scalar -> Character in
        invalid.contains(scalar) ? "-" : Character(scalar)
    }
    let sanitized = String(components)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized
}

private func sanitizeFolderToken(_ value: String) -> String {
    let replaced = value
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
        .replacingOccurrences(of: ":", with: "-")
    return sanitizeFileName(replaced)
}

private func formatDate(_ date: Date, pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = pattern
    return formatter.string(from: date)
}

private func makeAnalysisSnapshot(from job: JobRecord, classCodeFallback: String?) -> AnalysisResponse? {
    let hasUsefulData = job.analysisTypeDoc != nil
        || !(job.analysisSujets ?? []).isEmpty
        || !(job.analysisChamps ?? [:]).isEmpty
        || job.confidence != nil
        || job.suggestedPreset != nil
        || job.suggestedClassCode != nil
        || classCodeFallback != nil
    guard hasUsefulData else {
        return nil
    }

    let typeDoc = nonEmpty(job.analysisTypeDoc) ?? "autre"
    let sujets = (job.analysisSujets ?? []).filter { nonEmpty($0) != nil }
    let safeSujets = sujets.isEmpty ? ["general"] : sujets
    let champs = job.analysisChamps ?? [:]
    let pages = Int(champs["pages"] ?? "") ?? 0

    return AnalysisResponse(
        type_doc: typeDoc,
        sujets: safeSujets,
        structure: AnalysisStructure(
            has_signature: false,
            pages: max(0, pages)
        ),
        champs: champs,
        confidence: job.confidence ?? 0,
        suggested_preset: job.suggestedPreset,
        suggested_class_code: nonEmpty(job.suggestedClassCode) ?? nonEmpty(classCodeFallback),
        explanations: AnalysisExplanations(
            matched_rules: ["snapshot_persisted_job"],
            top_nodes: safeSujets
        ),
        capture: nil,
        review: nil
    )
}

private func selectRoutingRule(
    rules: [RoutingRule],
    classCode: String?,
    analysis: AnalysisResponse?
) -> RoutingRule? {
    var selected: (rule: RoutingRule, score: Int)?
    for rule in rules {
        guard routingRuleMatches(rule, classCode: classCode, analysis: analysis) else {
            continue
        }
        let score = routingRuleSpecificity(rule)
        if let current = selected, current.score >= score {
            continue
        }
        selected = (rule, score)
    }
    return selected?.rule
}

private func routingRuleMatches(
    _ rule: RoutingRule,
    classCode: String?,
    analysis: AnalysisResponse?
) -> Bool {
    let normalizedClassCode = normalizeRoutingToken(classCode)
    let normalizedType = normalizeRoutingToken(analysis?.type_doc)
    let normalizedSujets = (analysis?.sujets ?? [])
        .compactMap { normalizeRoutingToken($0) }

    if let expectedClass = normalizeRoutingToken(rule.when_class_code) {
        guard normalizedClassCode == expectedClass else {
            return false
        }
    }

    if let expectedType = normalizeRoutingToken(rule.when_type_doc) {
        guard normalizedType == expectedType else {
            return false
        }
    }

    if let expectedSujet = normalizeRoutingToken(rule.when_sujet) {
        guard normalizedSujets.contains(where: { $0.contains(expectedSujet) || expectedSujet.contains($0) }) else {
            return false
        }
    }

    return true
}

private func routingRuleSpecificity(_ rule: RoutingRule) -> Int {
    var score = 0
    if nonEmpty(rule.when_class_code) != nil { score += 1 }
    if nonEmpty(rule.when_type_doc) != nil { score += 1 }
    if nonEmpty(rule.when_sujet) != nil { score += 1 }
    return score
}

private func normalizeRoutingToken(_ raw: String?) -> String? {
    guard let raw = nonEmpty(raw) else {
        return nil
    }
    return raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
}

private func nonEmpty(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func uniqueDestinationURL(in directory: URL, proposedFileName: String) -> URL {
    let ext = URL(fileURLWithPath: proposedFileName).pathExtension
    let stem = URL(fileURLWithPath: proposedFileName).deletingPathExtension().lastPathComponent
    var candidate = directory.appendingPathComponent(proposedFileName)
    var suffix = 1

    while FileManager.default.fileExists(atPath: candidate.path) {
        let nextName: String
        if ext.isEmpty {
            nextName = "\(stem)-\(suffix)"
        } else {
            nextName = "\(stem)-\(suffix).\(ext)"
        }
        candidate = directory.appendingPathComponent(nextName)
        suffix += 1
    }
    return candidate
}

private func replaceFileExtension(_ fileName: String, with newExtension: String) -> String {
    let url = URL(fileURLWithPath: fileName)
    let stem = url.deletingPathExtension().lastPathComponent
    return "\(stem).\(newExtension)"
}

private func pdfaWarningsRequireReview(_ warnings: [String]) -> Bool {
    guard parseBooleanEnv("ORCHIVISTE_PDFA_FAILURE_NEEDS_REVIEW") else {
        return false
    }
    let triggers: Set<String> = [
        "pdfa_requested_but_ghostscript_missing",
        "pdfa_conversion_failed",
        "pdfa_move_failed"
    ]
    return warnings.contains { triggers.contains($0) }
}

private func parseBooleanEnv(_ key: String) -> Bool {
    guard let raw = Environment.get(key)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(),
          !raw.isEmpty else {
        return false
    }
    return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
}
