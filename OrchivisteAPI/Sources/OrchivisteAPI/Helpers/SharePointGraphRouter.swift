import Foundation
import Vapor

enum SharePointGraphRouter {
    struct RouteResult {
        let destinationURL: String?
        let movedItemID: String?
        let fileName: String
        let warnings: [String]
        let requiresReview: Bool
    }

    private struct GraphConfig {
        let tenantID: String
        let clientID: String
        let clientSecret: String
        let baseURL: String
        let authBaseURL: String
        let copyTimeoutMS: Int
        let copyPollIntervalMS: Int
        let deleteSourceAfterCopy: Bool
    }

    private struct GraphTokenResponse: Content {
        let access_token: String
    }

    private struct GraphDriveListResponse: Content {
        let value: [GraphDrive]
    }

    private struct GraphDrive: Content {
        let id: String
        let name: String
    }

    private struct GraphItem: Content {
        let id: String?
        let name: String?
        let webUrl: String?
    }

    private struct GraphFolderCreateRequest: Content {
        let name: String
        let folder: [String: String]
        let conflictBehavior: String

        enum CodingKeys: String, CodingKey {
            case name
            case folder
            case conflictBehavior = "@microsoft.graph.conflictBehavior"
        }
    }

    private struct GraphMoveRequest: Content {
        let name: String
        let parentReference: GraphParentReference
    }

    private struct GraphCopyRequest: Content {
        let name: String
        let parentReference: GraphParentReference
    }

    private struct GraphParentReference: Content {
        let id: String
        let driveId: String?
    }

    private struct GraphCopyOperation: Content {
        let status: String?
        let resourceId: String?
        let resourceLocation: String?
        let error: GraphErrorDetail?
    }

    private struct GraphErrorEnvelope: Content {
        let error: GraphErrorDetail?
    }

    private struct GraphErrorDetail: Content {
        let code: String?
        let message: String?
    }

    static func routeIfEnabled(
        job: JobRecord,
        target: RoutingTarget,
        resolvedFolder: String,
        classCode: String,
        preferredFileName: String?,
        req: Request
    ) async throws -> RouteResult? {
        guard graphEnabled() else {
            return nil
        }
        guard job.source.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sharepoint" else {
            return nil
        }

        let config = try loadConfig()
        let correlationID = req.headers.first(name: "x-correlation-id")

        guard let sourceItemID = nonEmpty(job.source.itemId) else {
            throw Abort(.badRequest, reason: "La source SharePoint ne contient pas itemId.")
        }
        guard let targetSiteID = nonEmpty(target.site) else {
            throw Abort(.badRequest, reason: "L'identifiant du site SharePoint cible est manquant.")
        }
        guard let targetLibrary = nonEmpty(target.library) else {
            throw Abort(.badRequest, reason: "L'identifiant de bibliotheque SharePoint cible est manquant.")
        }

        let sourceSiteID = nonEmpty(job.source.site) ?? targetSiteID
        let sourceLibrary = nonEmpty(job.source.library) ?? targetLibrary
        let routedName = nonEmpty(preferredFileName)
            ?? routedFileName(classCode: classCode, original: originalFileName(from: job.fileURL))

        let token = try await fetchAccessToken(
            config: config,
            req: req,
            correlationID: correlationID
        )
        let sourceDriveID = try await resolveDriveID(
            siteID: sourceSiteID,
            library: sourceLibrary,
            token: token,
            config: config,
            req: req,
            correlationID: correlationID
        )
        let targetDriveID = try await resolveDriveID(
            siteID: targetSiteID,
            library: targetLibrary,
            token: token,
            config: config,
            req: req,
            correlationID: correlationID
        )
        let folderID = try await ensureFolderPath(
            driveID: targetDriveID,
            resolvedFolder: resolvedFolder,
            token: token,
            config: config,
            req: req,
            correlationID: correlationID
        )

        if sourceDriveID == targetDriveID {
            let movedItem = try await moveItem(
                driveID: sourceDriveID,
                sourceItemID: sourceItemID,
                destinationDriveID: targetDriveID,
                destinationFolderID: folderID,
                newName: routedName,
                token: token,
                config: config,
                req: req,
                correlationID: correlationID
            )

            return RouteResult(
                destinationURL: movedItem.webUrl,
                movedItemID: movedItem.id,
                fileName: nonEmpty(movedItem.name) ?? routedName,
                warnings: [],
                requiresReview: false
            )
        }

        let copiedItem = try await copyItem(
            sourceDriveID: sourceDriveID,
            sourceItemID: sourceItemID,
            targetDriveID: targetDriveID,
            destinationFolderID: folderID,
            newName: routedName,
            token: token,
            config: config,
            req: req,
            correlationID: correlationID
        )

        var warnings: [String] = []
        var requiresReview = false
        if config.deleteSourceAfterCopy {
            do {
                let deleted = try await deleteItem(
                    driveID: sourceDriveID,
                    itemID: sourceItemID,
                    token: token,
                    config: config,
                    req: req,
                    correlationID: correlationID
                )
                if !deleted {
                    warnings.append("graph_source_delete_failed")
                    requiresReview = true
                }
            } catch {
                req.logger.warning("Le nettoyage de la source SharePoint apres copie a echoue.", metadata: [
                    "job_id": .string(job.id.uuidString),
                    "error": .string(error.localizedDescription)
                ])
                warnings.append("graph_source_delete_failed")
                requiresReview = true
            }
        }

        return RouteResult(
            destinationURL: copiedItem.webUrl,
            movedItemID: copiedItem.id,
            fileName: nonEmpty(copiedItem.name) ?? routedName,
            warnings: warnings,
            requiresReview: requiresReview
        )
    }

    private static func graphEnabled() -> Bool {
        parseBooleanEnv("ORCHIVISTE_GRAPH_ENABLED")
    }

    private static func loadConfig() throws -> GraphConfig {
        guard let tenantID = nonEmpty(Environment.get("ORCHIVISTE_GRAPH_TENANT_ID")),
              let clientID = nonEmpty(Environment.get("ORCHIVISTE_GRAPH_CLIENT_ID")),
              let clientSecret = nonEmpty(Environment.get("ORCHIVISTE_GRAPH_CLIENT_SECRET")) else {
            throw Abort(.internalServerError, reason: "Le routage Graph est active mais les identifiants Graph sont incomplets.")
        }

        let baseURL = trimTrailingSlash(
            Environment.get("ORCHIVISTE_GRAPH_BASE_URL") ?? "https://graph.microsoft.com/v1.0"
        )
        let authBaseURL = trimTrailingSlash(
            Environment.get("ORCHIVISTE_GRAPH_AUTH_BASE_URL") ?? "https://login.microsoftonline.com"
        )
        let copyTimeoutMS = max(2_000, Int(Environment.get("ORCHIVISTE_GRAPH_COPY_TIMEOUT_MS") ?? "20000") ?? 20_000)
        let copyPollIntervalMS = max(100, Int(Environment.get("ORCHIVISTE_GRAPH_COPY_POLL_INTERVAL_MS") ?? "250") ?? 250)

        return GraphConfig(
            tenantID: tenantID,
            clientID: clientID,
            clientSecret: clientSecret,
            baseURL: baseURL,
            authBaseURL: authBaseURL,
            copyTimeoutMS: copyTimeoutMS,
            copyPollIntervalMS: copyPollIntervalMS,
            deleteSourceAfterCopy: parseBooleanEnv("ORCHIVISTE_GRAPH_DELETE_SOURCE_AFTER_COPY", defaultValue: true)
        )
    }

    private static func fetchAccessToken(
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> String {
        let tokenURI = URI(string: "\(config.authBaseURL)/\(config.tenantID)/oauth2/v2.0/token")
        let body = formURLEncoded([
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "scope": "https://graph.microsoft.com/.default",
            "grant_type": "client_credentials"
        ])

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "application/x-www-form-urlencoded")
        headers.replaceOrAdd(name: .accept, value: "application/json")
        if let correlationID, !correlationID.isEmpty {
            headers.replaceOrAdd(name: "x-correlation-id", value: correlationID)
        }

        let response = try await req.client.post(tokenURI, headers: headers) { outgoing in
            outgoing.body = .init(string: body)
        }
        guard response.status == .ok else {
            throw graphError(
                status: .internalServerError,
                reason: "Impossible d'obtenir un jeton d'accès Microsoft Graph.",
                response: response
            )
        }

        let payload = try response.content.decode(GraphTokenResponse.self)
        guard !payload.access_token.isEmpty else {
            throw Abort(.internalServerError, reason: "Jeton d'accès Graph vide reçu.")
        }
        return payload.access_token
    }

    private static func resolveDriveID(
        siteID: String,
        library: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> String {
        if looksLikeResourceID(library) {
            return library
        }

        let uri = graphURI(
            baseURL: config.baseURL,
            path: "/sites/\(encodePathSegment(siteID))/drives?$select=id,name"
        )
        let response = try await req.client.get(
            uri,
            headers: graphHeaders(token: token, correlationID: correlationID)
        )
        guard response.status == .ok else {
            throw graphError(
                status: .badGateway,
                reason: "Impossible de resoudre le lecteur SharePoint.",
                response: response
            )
        }

        let payload = try response.content.decode(GraphDriveListResponse.self)
        guard let drive = payload.value.first(where: { $0.name.caseInsensitiveCompare(library) == .orderedSame }) else {
            throw Abort(.notFound, reason: "Bibliotheque SharePoint '\(library)' introuvable sur le site '\(siteID)'.")
        }
        return drive.id
    }

    private static func ensureFolderPath(
        driveID: String,
        resolvedFolder: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> String {
        let segments = resolvedFolder
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if segments.isEmpty {
            return "root"
        }

        var parentID = "root"
        for segment in segments {
            let uri = graphURI(
                baseURL: config.baseURL,
                path: "/drives/\(encodePathSegment(driveID))/items/\(encodePathSegment(parentID))/children"
            )
            let payload = GraphFolderCreateRequest(
                name: segment,
                folder: [:],
                conflictBehavior: "replace"
            )

            let response = try await req.client.post(
                uri,
                headers: graphHeaders(token: token, correlationID: correlationID)
            ) { outgoing in
                try outgoing.content.encode(payload)
            }
            guard response.status.code >= 200, response.status.code < 300 else {
                throw graphError(
                    status: .badGateway,
                    reason: "Impossible de creer ou resoudre le dossier de destination '\(segment)'.",
                    response: response
                )
            }

            let created = try response.content.decode(GraphItem.self)
            guard let id = nonEmpty(created.id) else {
                throw Abort(.badGateway, reason: "Graph a retourne une charge dossier invalide pour '\(segment)'.")
            }
            parentID = id
        }

        return parentID
    }

    private static func moveItem(
        driveID: String,
        sourceItemID: String,
        destinationDriveID: String,
        destinationFolderID: String,
        newName: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> GraphItem {
        let uri = graphURI(
            baseURL: config.baseURL,
            path: "/drives/\(encodePathSegment(driveID))/items/\(encodePathSegment(sourceItemID))"
        )
        let payload = GraphMoveRequest(
            name: newName,
            parentReference: GraphParentReference(
                id: destinationFolderID,
                driveId: destinationDriveID
            )
        )

        let response = try await req.client.patch(
            uri,
            headers: graphHeaders(token: token, correlationID: correlationID)
        ) { outgoing in
            try outgoing.content.encode(payload)
        }
        guard response.status == .ok else {
            throw graphError(
                status: .badGateway,
                reason: "Impossible de deplacer le fichier SharePoint vers le dossier cible.",
                response: response
            )
        }

        return try response.content.decode(GraphItem.self)
    }

    private static func copyItem(
        sourceDriveID: String,
        sourceItemID: String,
        targetDriveID: String,
        destinationFolderID: String,
        newName: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> GraphItem {
        let uri = graphURI(
            baseURL: config.baseURL,
            path: "/drives/\(encodePathSegment(sourceDriveID))/items/\(encodePathSegment(sourceItemID))/copy"
        )
        let payload = GraphCopyRequest(
            name: newName,
            parentReference: GraphParentReference(
                id: destinationFolderID,
                driveId: targetDriveID
            )
        )

        let response = try await req.client.post(
            uri,
            headers: graphHeaders(token: token, correlationID: correlationID)
        ) { outgoing in
            try outgoing.content.encode(payload)
        }
        guard response.status == .accepted else {
            throw graphError(
                status: .badGateway,
                reason: "Impossible de copier le fichier SharePoint vers le lecteur cible.",
                response: response
            )
        }
        guard let operationLocation = nonEmpty(response.headers.first(name: "Location")) else {
            throw Abort(.badGateway, reason: "Graph n'a pas retourne d'URL d'operation de copie.")
        }

        return try await pollCopyOperation(
            operationLocation: operationLocation,
            targetDriveID: targetDriveID,
            token: token,
            config: config,
            req: req,
            correlationID: correlationID
        )
    }

    private static func pollCopyOperation(
        operationLocation: String,
        targetDriveID: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> GraphItem {
        let operationURI = absoluteURI(operationLocation, baseURL: config.baseURL)
        let deadline = Date().addingTimeInterval(Double(config.copyTimeoutMS) / 1000.0)

        while Date() <= deadline {
            let response = try await req.client.get(
                operationURI,
                headers: graphHeaders(token: token, correlationID: correlationID)
            )

            if response.status == .accepted {
                try await Task.sleep(nanoseconds: UInt64(config.copyPollIntervalMS) * 1_000_000)
                continue
            }

            guard response.status.code >= 200, response.status.code < 300 else {
                throw graphError(
                    status: .badGateway,
                    reason: "Impossible de suivre l'operation de copie Graph.",
                    response: response
                )
            }

            if let item = try? response.content.decode(GraphItem.self),
               nonEmpty(item.id) != nil {
                return item
            }

            let payload = try response.content.decode(GraphCopyOperation.self)
            let status = payload.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if status == "failed" {
                let detail = nonEmpty(payload.error?.message) ?? "Operation de copie Graph en echec."
                throw Abort(.badGateway, reason: detail)
            }
            if status == "completed" || status == "succeeded" || !status.isEmpty {
                if let resourceLocation = nonEmpty(payload.resourceLocation) {
                    return try await fetchItem(
                        at: resourceLocation,
                        token: token,
                        config: config,
                        req: req,
                        correlationID: correlationID
                    )
                }
                if let resourceID = nonEmpty(payload.resourceId) {
                    return try await fetchItem(
                        driveID: targetDriveID,
                        itemID: resourceID,
                        token: token,
                        config: config,
                        req: req,
                        correlationID: correlationID
                    )
                }
                if status == "completed" || status == "succeeded" {
                    throw Abort(.badGateway, reason: "Graph a signale une copie terminee sans resourceId ni resourceLocation.")
                }
            }

            try await Task.sleep(nanoseconds: UInt64(config.copyPollIntervalMS) * 1_000_000)
        }

        throw Abort(.gatewayTimeout, reason: "Le delai d'attente de la copie Graph est depasse.")
    }

    private static func fetchItem(
        driveID: String,
        itemID: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> GraphItem {
        let uri = graphURI(
            baseURL: config.baseURL,
            path: "/drives/\(encodePathSegment(driveID))/items/\(encodePathSegment(itemID))"
        )
        return try await fetchItem(
            at: uri.string,
            token: token,
            config: config,
            req: req,
            correlationID: correlationID
        )
    }

    private static func fetchItem(
        at location: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> GraphItem {
        let response = try await req.client.get(
            absoluteURI(location, baseURL: config.baseURL),
            headers: graphHeaders(token: token, correlationID: correlationID)
        )
        guard response.status.code >= 200, response.status.code < 300 else {
            throw graphError(
                status: .badGateway,
                reason: "Impossible de recuperer l'item Graph apres copie.",
                response: response
            )
        }
        return try response.content.decode(GraphItem.self)
    }

    private static func deleteItem(
        driveID: String,
        itemID: String,
        token: String,
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> Bool {
        let uri = graphURI(
            baseURL: config.baseURL,
            path: "/drives/\(encodePathSegment(driveID))/items/\(encodePathSegment(itemID))"
        )
        let response = try await req.client.delete(
            uri,
            headers: graphHeaders(token: token, correlationID: correlationID)
        )
        return response.status == .noContent || response.status == .ok || response.status == .accepted
    }

    private static func originalFileName(from raw: String) -> String {
        if let parsed = URL(string: raw), !parsed.lastPathComponent.isEmpty {
            return parsed.lastPathComponent
        }
        return URL(fileURLWithPath: raw).lastPathComponent
    }

    private static func routedFileName(classCode: String, original: String) -> String {
        let ext = URL(fileURLWithPath: original).pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        if ext.isEmpty {
            return "\(classCode)-\(stamp)"
        }
        return "\(classCode)-\(stamp).\(ext)"
    }

    private static func graphHeaders(token: String, correlationID: String?) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token)
        headers.replaceOrAdd(name: .accept, value: "application/json")
        headers.replaceOrAdd(name: .contentType, value: "application/json")
        if let correlationID, !correlationID.isEmpty {
            headers.replaceOrAdd(name: "x-correlation-id", value: correlationID)
        }
        return headers
    }

    private static func graphURI(baseURL: String, path: String) -> URI {
        URI(string: "\(trimTrailingSlash(baseURL))\(path)")
    }

    private static func absoluteURI(_ raw: String, baseURL: String) -> URI {
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return URI(string: raw)
        }
        if raw.hasPrefix("/") {
            return URI(string: "\(trimTrailingSlash(baseURL))\(raw)")
        }
        return URI(string: "\(trimTrailingSlash(baseURL))/\(raw)")
    }

    private static func trimTrailingSlash(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func looksLikeResourceID(_ value: String) -> Bool {
        value.contains("!") || value.hasPrefix("b!") || value.contains(",")
    }

    private static func encodePathSegment(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    private static func formURLEncoded(_ values: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return values
            .map { key, value in
                let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(escapedKey)=\(escapedValue)"
            }
            .sorted()
            .joined(separator: "&")
    }

    private static func parseBooleanEnv(_ key: String, defaultValue: Bool = false) -> Bool {
        guard let raw = Environment.get(key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !raw.isEmpty else {
            return defaultValue
        }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func graphError(
        status: HTTPStatus,
        reason: String,
        response: ClientResponse
    ) -> Abort {
        var detail = ""
        if let decoded = try? response.content.decode(GraphErrorEnvelope.self),
           let message = decoded.error?.message,
           !message.isEmpty {
            detail = message
        } else if var body = response.body,
                  let text = body.readString(length: body.readableBytes) {
            detail = text
        }
        if detail.count > 300 {
            detail = String(detail.prefix(300))
        }
        let suffix = detail.isEmpty ? "" : " Réponse Graph: \(detail)"
        return Abort(status, reason: "\(reason) (status \(response.status.code)).\(suffix)")
    }
}
