import Foundation
import Vapor

func registerPreviewRoutes(_ app: Application) {
    app.group("v1", "preview") { preview in
        preview.get(":id", "thumbnail") { req async throws -> Response in
            guard let id = req.parameters.get("id"),
                  let jobId = UUID(uuidString: id) else {
                throw Abort(.badRequest, reason: "Identifiant d'aperçu invalide.")
            }
            guard let record = try await PreviewLoader.ensurePreview(jobId: jobId, req: req) else {
                throw Abort(.notFound, reason: "Aperçu non disponible.")
            }
            let image = record.imagesByPage[1] ?? PreviewHelper.placeholderJPEG()
            return RangeResponse.make(req: req, data: image, contentType: .jpeg)
        }

        let pageHandler: (Request) async throws -> Response = { req in
            guard let id = req.parameters.get("id"),
                  let jobId = UUID(uuidString: id) else {
                throw Abort(.badRequest, reason: "Identifiant d'aperçu invalide.")
            }
            let rawPage = req.parameters.get("n") ?? req.parameters.get("n.jpg") ?? ""
            let normalizedPage = rawPage.hasSuffix(".jpg")
                ? String(rawPage.dropLast(4))
                : rawPage
            guard let page = Int(normalizedPage),
                  page > 0 else {
                throw Abort(.badRequest, reason: "Numéro de page d'aperçu invalide.")
            }
            guard let record = try await PreviewLoader.ensurePreview(jobId: jobId, req: req) else {
                throw Abort(.notFound, reason: "Page d'aperçu introuvable.")
            }
            let image = record.imagesByPage[page] ?? PreviewHelper.placeholderJPEG()
            return RangeResponse.make(req: req, data: image, contentType: .jpeg)
        }

        preview.get(":id", "page", ":n", use: pageHandler)

        preview.get(":id", "text") { req async throws -> PreviewTextResponse in
            guard let id = req.parameters.get("id"),
                  let jobId = UUID(uuidString: id) else {
                throw Abort(.badRequest, reason: "Identifiant d'aperçu invalide.")
            }
            guard let record = try await PreviewLoader.ensurePreview(jobId: jobId, req: req) else {
                throw Abort(.notFound, reason: "Aperçu non disponible.")
            }
            let page = (try? req.query.get(Int.self, at: "page")) ?? 1
            guard page > 0 else {
                throw Abort(.badRequest, reason: "Parametre page invalide.")
            }
            if let existing = record.textPages[page],
               !PreviewHelper.isDefaultText(existing, page: page) {
                return PreviewTextResponse(page: page, text: existing)
            }

            if let supplemental = try await loadSupplementalPreviewText(
                jobId: jobId,
                page: page,
                req: req
            ) {
                return PreviewTextResponse(page: page, text: supplemental)
            }

            let text = record.textPages[page] ?? PreviewHelper.defaultText(page: page)
            return PreviewTextResponse(page: page, text: text)
        }

        preview.get(":id", "office") { req async throws -> Response in
            guard let id = req.parameters.get("id"),
                  let jobId = UUID(uuidString: id) else {
                throw Abort(.badRequest, reason: "Identifiant d'aperçu invalide.")
            }
            let inMemory = await req.application.appState.job(id: jobId)
            let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: req.db)
            guard let job = inMemory ?? persisted else {
                throw Abort(.notFound, reason: "Tâche introuvable.")
            }
            guard job.source.kind.lowercased() == "sharepoint",
                  let url = job.source.url else {
                throw Abort(.notFound, reason: "L'aperçu Office Online est disponible uniquement pour les sources SharePoint.")
            }
            return req.redirect(to: url)
        }
    }
}

private func loadSupplementalPreviewText(
    jobId: UUID,
    page: Int,
    req: Request
) async throws -> String? {
    let inMemory = await req.application.appState.job(id: jobId)
    let persisted = try await JobPersistenceRepository.fetchJob(id: jobId, on: req.db)
    guard let job = inMemory ?? persisted else {
        return nil
    }
    guard job.source.kind.lowercased() == "local",
          let localFileURL = resolvePreviewLocalFileURL(raw: job.fileURL),
          FileManager.default.fileExists(atPath: localFileURL.path) else {
        return nil
    }
    guard let extracted = DocumentTextExtractor.extract(fileURL: localFileURL, logger: req.logger) else {
        return nil
    }
    defer {
        for artifact in extracted.temporaryArtifacts {
            try? FileManager.default.removeItem(at: artifact)
        }
    }

    guard extracted.pages.indices.contains(page - 1) else {
        return nil
    }
    let text = extracted.pages[page - 1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
        return nil
    }
    return text
}

private func resolvePreviewLocalFileURL(raw: String) -> URL? {
    if let url = URL(string: raw), url.isFileURL {
        return url
    }
    if raw.hasPrefix("/") {
        return URL(fileURLWithPath: raw)
    }
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return current.appendingPathComponent(raw)
}
