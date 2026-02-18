import Foundation
import Vapor

private struct LocalRouteResult {
    let destinationPath: String
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
    guard let routing = ConfigLoader.loadRoutingMap() else {
        throw Abort(.notFound, reason: "Table de routage introuvable.")
    }
    let routeRequest = try? req.content.decode(RoutingRequest.self)
    let localSettings = ConfigLoader.loadRoutingLocalSettings()
    let routingRules = ConfigLoader.loadRoutingRules()
    let presets = ConfigLoader.loadPresets()

    var suggestedCode: String?
    var resolvedJobID: UUID?
    var resolvedJob: JobRecord?
    if let jobId = UUID(uuidString: fileId) {
        let inMemory = await req.application.appState.job(id: jobId)
        let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: req.db)
        if let job = inMemory ?? persisted {
            await req.application.appState.cacheJob(job)
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
        analysis = await req.application.appState.analysis(jobId: resolvedJobID)
    }
    if analysis == nil, let resolvedJob {
        analysis = makeAnalysisSnapshot(from: resolvedJob, classCodeFallback: resolvedJob.suggestedClassCode)
    }

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
        ?? nonEmpty(localSettings?.default_destination_template)
        ?? target.folder_expr
    let resolved = resolveFolderTemplate(
        template: folderTemplate,
        classCode: effectiveClassCode,
        analysis: analysis,
        presetID: selectedPreset?.id
    )

    var resolvedFileName: String?
    if let resolvedJob {
        let originalName = URL(fileURLWithPath: resolvedJob.fileURL).lastPathComponent
        let effectiveNameFormat = nonEmpty(routeRequest?.name_format)
            ?? nonEmpty(selectedRule?.name_format)
            ?? nonEmpty(selectedPreset?.name_format)
            ?? nonEmpty(localSettings?.default_name_format)
        resolvedFileName = buildRoutedFileName(
            classCode: effectiveClassCode,
            originalName: originalName,
            analysis: analysis,
            presetID: selectedPreset?.id,
            jobID: resolvedJob.id.uuidString,
            nameFormat: effectiveNameFormat,
            postprocess: selectedPreset?.postprocess ?? []
        )
    }

    var routeMode = "stub"
    var destinationURL: String?
    var movedItemID: String?
    var destinationLocalPath: String?

    if let resolvedJob {
        do {
            if let graphRoute = try await SharePointGraphRouter.routeIfEnabled(
                job: resolvedJob,
                target: target,
                resolvedFolder: resolved,
                classCode: effectiveClassCode,
                req: req
            ) {
                routeMode = "graph"
                destinationURL = graphRoute.destinationURL
                movedItemID = graphRoute.movedItemID
                await EventPublisher.publish(
                    type: "route.graph_applied",
                    payload: [
                        "job_id": resolvedJob.id.uuidString,
                        "class_code": effectiveClassCode,
                        "mode": routeMode
                    ],
                    application: req.application,
                    database: req.db,
                    logger: req.logger
                )
            } else if let localRoute = try routeLocalFileIfPossible(
                job: resolvedJob,
                resolvedFolder: resolved,
                classCode: effectiveClassCode,
                localSettings: localSettings,
                preferredFileName: resolvedFileName,
                logger: req.logger
            ) {
                routeMode = "local"
                destinationLocalPath = localRoute.destinationPath
                resolvedFileName = localRoute.fileName
                await EventPublisher.publish(
                    type: "route.local_applied",
                    payload: [
                        "job_id": resolvedJob.id.uuidString,
                        "class_code": effectiveClassCode,
                        "mode": routeMode,
                        "file_name": localRoute.fileName,
                        "destination_path": localRoute.destinationPath
                    ],
                    application: req.application,
                    database: req.db,
                    logger: req.logger
                )
            }
        } catch {
            await EventPublisher.publish(
                type: "route.failed",
                payload: [
                    "job_id": resolvedJob.id.uuidString,
                    "class_code": effectiveClassCode
                ],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            throw error
        }
    }

    if let resolvedJobID,
       let updatedJob = await req.application.appState.markRouted(jobId: resolvedJobID, classCode: effectiveClassCode) {
        try await JobPersistenceRepository.upsert(job: updatedJob, on: req.db)
        await EventPublisher.publish(
            type: "job.routed",
            payload: [
                "job_id": resolvedJobID.uuidString,
                "class_code": effectiveClassCode,
                "mode": routeMode
            ],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
    } else {
        await EventPublisher.publish(
            type: "route.ready",
            payload: [
                "file_id": fileId,
                "class_code": effectiveClassCode,
                "mode": routeMode
            ],
            application: req.application,
            database: req.db,
            logger: req.logger
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

private func routeLocalFileIfPossible(
    job: JobRecord,
    resolvedFolder: String,
    classCode: String,
    localSettings: RoutingLocalSettings?,
    preferredFileName: String?,
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

    let destinationName = nonEmpty(preferredFileName) ?? routedLocalFileName(
        classCode: classCode,
        originalName: sourceURL.lastPathComponent
    )
    let destinationURL = uniqueDestinationURL(
        in: destinationDirectory,
        proposedFileName: destinationName
    )

    do {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    } catch {
        // cross-device move can fail on rename; fallback to copy+delete
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            try FileManager.default.removeItem(at: sourceURL)
        } catch {
            throw Abort(
                .internalServerError,
                reason: "Échec du routage local du fichier: \(error.localizedDescription)"
            )
        }
    }

    return LocalRouteResult(destinationPath: destinationURL.path, fileName: destinationURL.lastPathComponent)
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
    let dateStamp = formatDate(now, pattern: "yyyyMMdd")
    let dateTimeStamp = formatDate(now, pattern: "yyyyMMdd-HHmmss")
    let number = analysis?.champs["numero"] ?? String(UUID().uuidString.prefix(8))
    let committee = analysis?.champs["comite"] ?? "general"
    let typeDoc = analysis?.type_doc ?? "autre"
    let sujet = analysis?.sujets.first ?? "general"
    let sujets = (analysis?.sujets ?? ["general"]).joined(separator: "-")

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
    rawName = sanitizeFileName(rawName)
    if rawName.isEmpty {
        rawName = "\(classCode)-\(dateTimeStamp)"
    }
    if ext.isEmpty {
        return rawName
    }
    if rawName.lowercased().hasSuffix(".\(ext.lowercased())") {
        return rawName
    }
    return "\(rawName).\(ext)"
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
        )
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
