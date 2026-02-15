import Foundation
import Vapor

enum SharePointGraphRouter {
    struct RouteResult {
        let destinationURL: String?
        let movedItemID: String?
    }

    private struct GraphConfig {
        let tenantID: String
        let clientID: String
        let clientSecret: String
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

    private struct GraphParentReference: Content {
        let id: String
    }

    private struct GraphErrorEnvelope: Content {
        let error: GraphErrorDetail?
    }

    private struct GraphErrorDetail: Content {
        let message: String?
    }

    static func routeIfEnabled(
        job: JobRecord,
        target: RoutingTarget,
        resolvedFolder: String,
        classCode: String,
        req: Request
    ) async throws -> RouteResult? {
        guard graphEnabled() else {
            return nil
        }
        guard job.source.kind.lowercased() == "sharepoint" else {
            return nil
        }

        let config = try loadConfig()
        guard let sourceItemID = job.source.itemId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceItemID.isEmpty else {
            throw Abort(.badRequest, reason: "SharePoint source is missing itemId.")
        }

        let siteID = (job.source.site ?? target.site).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !siteID.isEmpty else {
            throw Abort(.badRequest, reason: "SharePoint site identifier is missing.")
        }

        let library = (job.source.library ?? target.library).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !library.isEmpty else {
            throw Abort(.badRequest, reason: "SharePoint library identifier is missing.")
        }

        let correlationID = req.headers.first(name: "x-correlation-id")
        let token = try await fetchAccessToken(config: config, req: req, correlationID: correlationID)
        let driveID = try await resolveDriveID(
            siteID: siteID,
            library: library,
            token: token,
            req: req,
            correlationID: correlationID
        )
        let folderID = try await ensureFolderPath(
            siteID: siteID,
            driveID: driveID,
            resolvedFolder: resolvedFolder,
            token: token,
            req: req,
            correlationID: correlationID
        )
        let routedName = routedFileName(classCode: classCode, original: originalFileName(from: job.fileURL))
        let movedItem = try await moveItem(
            siteID: siteID,
            driveID: driveID,
            sourceItemID: sourceItemID,
            destinationFolderID: folderID,
            newName: routedName,
            token: token,
            req: req,
            correlationID: correlationID
        )

        return RouteResult(
            destinationURL: movedItem.webUrl,
            movedItemID: movedItem.id
        )
    }

    private static func graphEnabled() -> Bool {
        let raw = (Environment.get("ORCHIVISTE_GRAPH_ENABLED") ?? "").lowercased()
        return raw == "1" || raw == "true" || raw == "yes"
    }

    private static func loadConfig() throws -> GraphConfig {
        guard let tenantID = Environment.get("ORCHIVISTE_GRAPH_TENANT_ID"),
              !tenantID.isEmpty,
              let clientID = Environment.get("ORCHIVISTE_GRAPH_CLIENT_ID"),
              !clientID.isEmpty,
              let clientSecret = Environment.get("ORCHIVISTE_GRAPH_CLIENT_SECRET"),
              !clientSecret.isEmpty else {
            throw Abort(.internalServerError, reason: "Graph routing is enabled but Graph credentials are not fully configured.")
        }
        return GraphConfig(tenantID: tenantID, clientID: clientID, clientSecret: clientSecret)
    }

    private static func fetchAccessToken(
        config: GraphConfig,
        req: Request,
        correlationID: String?
    ) async throws -> String {
        let tokenURI = URI(string: "https://login.microsoftonline.com/\(config.tenantID)/oauth2/v2.0/token")
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
                reason: "Unable to acquire Microsoft Graph access token.",
                response: response
            )
        }

        let payload = try response.content.decode(GraphTokenResponse.self)
        guard !payload.access_token.isEmpty else {
            throw Abort(.internalServerError, reason: "Received empty Graph access token.")
        }
        return payload.access_token
    }

    private static func resolveDriveID(
        siteID: String,
        library: String,
        token: String,
        req: Request,
        correlationID: String?
    ) async throws -> String {
        if looksLikeResourceID(library) {
            return library
        }

        let uri = graphURI(path: "/sites/\(siteID)/drives?$select=id,name")
        let response = try await req.client.get(uri, headers: graphHeaders(token: token, correlationID: correlationID))
        guard response.status == .ok else {
            throw graphError(
                status: .badGateway,
                reason: "Unable to resolve SharePoint drive.",
                response: response
            )
        }

        let payload = try response.content.decode(GraphDriveListResponse.self)
        guard let drive = payload.value.first(where: { $0.name.caseInsensitiveCompare(library) == .orderedSame }) else {
            throw Abort(.notFound, reason: "SharePoint library '\(library)' not found on site '\(siteID)'.")
        }
        return drive.id
    }

    private static func ensureFolderPath(
        siteID: String,
        driveID: String,
        resolvedFolder: String,
        token: String,
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
            let uri = graphURI(path: "/sites/\(siteID)/drives/\(encodePathSegment(driveID))/items/\(encodePathSegment(parentID))/children")
            let payload = GraphFolderCreateRequest(
                name: segment,
                folder: [:],
                conflictBehavior: "replace"
            )

            let response = try await req.client.post(uri, headers: graphHeaders(token: token, correlationID: correlationID)) { outgoing in
                try outgoing.content.encode(payload)
            }
            guard response.status.code >= 200, response.status.code < 300 else {
                throw graphError(
                    status: .badGateway,
                    reason: "Unable to create or resolve destination folder '\(segment)'.",
                    response: response
                )
            }

            let created = try response.content.decode(GraphItem.self)
            guard let id = created.id, !id.isEmpty else {
                throw Abort(.badGateway, reason: "Graph returned an invalid folder payload for '\(segment)'.")
            }
            parentID = id
        }
        return parentID
    }

    private static func moveItem(
        siteID: String,
        driveID: String,
        sourceItemID: String,
        destinationFolderID: String,
        newName: String,
        token: String,
        req: Request,
        correlationID: String?
    ) async throws -> GraphItem {
        let uri = graphURI(path: "/sites/\(siteID)/drives/\(encodePathSegment(driveID))/items/\(encodePathSegment(sourceItemID))")
        let payload = GraphMoveRequest(
            name: newName,
            parentReference: GraphParentReference(id: destinationFolderID)
        )

        let response = try await req.client.patch(uri, headers: graphHeaders(token: token, correlationID: correlationID)) { outgoing in
            try outgoing.content.encode(payload)
        }
        guard response.status == .ok else {
            throw graphError(
                status: .badGateway,
                reason: "Unable to move SharePoint file to destination folder.",
                response: response
            )
        }

        return try response.content.decode(GraphItem.self)
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

    private static func graphURI(path: String) -> URI {
        URI(string: "https://graph.microsoft.com/v1.0\(path)")
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

    private static func graphError(
        status: HTTPStatus,
        reason: String,
        response: ClientResponse
    ) -> Abort {
        var detail = ""
        if var body = response.body,
           let text = body.readString(length: body.readableBytes) {
            detail = text
        }
        if let decoded = try? response.content.decode(GraphErrorEnvelope.self),
           let message = decoded.error?.message,
           !message.isEmpty {
            detail = message
        }
        if detail.count > 300 {
            detail = String(detail.prefix(300))
        }
        let suffix = detail.isEmpty ? "" : " Graph said: \(detail)"
        return Abort(status, reason: "\(reason) (status \(response.status.code)).\(suffix)")
    }
}
