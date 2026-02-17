import Foundation
import Vapor

private struct LocalRouteResult {
    let destinationPath: String
}

func registerRoutingRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("route", ":file_id") { req async throws -> RoutingResponse in
            guard let fileId = req.parameters.get("file_id") else {
                throw Abort(.badRequest, reason: "file_id est requis.")
            }
            guard let routing = ConfigLoader.loadRoutingMap() else {
                throw Abort(.notFound, reason: "Table de routage introuvable.")
            }

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

            let classCode = suggestedCode ?? routing.mappings.keys.first ?? "UNCLASSIFIED"

            guard let target = routing.mappings[classCode] ?? routing.mappings.values.first else {
                throw Abort(.notFound, reason: "Aucune cible de routage pour ce code de classement.")
            }

            let year = String(Calendar.current.component(.year, from: Date()))
            let resolved = target.folder_expr
                .replacingOccurrences(of: "{code}", with: classCode)
                .replacingOccurrences(of: "{year}", with: year)

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
                        classCode: classCode,
                        req: req
                    ) {
                        routeMode = "graph"
                        destinationURL = graphRoute.destinationURL
                        movedItemID = graphRoute.movedItemID
                        await EventPublisher.publish(
                            type: "route.graph_applied",
                            payload: [
                                "job_id": resolvedJob.id.uuidString,
                                "class_code": classCode,
                                "mode": routeMode
                            ],
                            application: req.application,
                            database: req.db,
                            logger: req.logger
                        )
                    } else if let localRoute = try routeLocalFileIfPossible(
                        job: resolvedJob,
                        resolvedFolder: resolved,
                        classCode: classCode,
                        logger: req.logger
                    ) {
                        routeMode = "local"
                        destinationLocalPath = localRoute.destinationPath
                        await EventPublisher.publish(
                            type: "route.local_applied",
                            payload: [
                                "job_id": resolvedJob.id.uuidString,
                                "class_code": classCode,
                                "mode": routeMode,
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
                            "class_code": classCode
                        ],
                        application: req.application,
                        database: req.db,
                        logger: req.logger
                    )
                    throw error
                }
            }

            if let resolvedJobID,
               let updatedJob = await req.application.appState.markRouted(jobId: resolvedJobID, classCode: classCode) {
                try await JobPersistenceRepository.upsert(job: updatedJob, on: req.db)
                await EventPublisher.publish(
                    type: "job.routed",
                    payload: [
                        "job_id": resolvedJobID.uuidString,
                        "class_code": classCode,
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
                        "class_code": classCode,
                        "mode": routeMode
                    ],
                    application: req.application,
                    database: req.db,
                    logger: req.logger
                )
            }

            return RoutingResponse(
                file_id: fileId,
                class_code: classCode,
                target: target,
                resolved_folder: resolved,
                mode: routeMode,
                destination_url: destinationURL,
                moved_item_id: movedItemID,
                destination_local_path: destinationLocalPath
            )
        }
    }
}

private func routeLocalFileIfPossible(
    job: JobRecord,
    resolvedFolder: String,
    classCode: String,
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

    let rootDirectory = localRoutingRootDirectory()
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

    let destinationName = routedLocalFileName(
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

    return LocalRouteResult(destinationPath: destinationURL.path)
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

private func localRoutingRootDirectory() -> URL {
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
