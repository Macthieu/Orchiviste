import Vapor

func registerPreviewRoutes(_ app: Application) {
    app.group("v1", "preview") { preview in
        preview.get(":id", "thumbnail") { req async throws -> Response in
            guard let id = req.parameters.get("id"),
                  let jobId = UUID(uuidString: id) else {
                throw Abort(.badRequest, reason: "Identifiant d'aperçu invalide.")
            }
            guard let record = await req.application.appState.preview(jobId: jobId),
                  let image = record.imagesByPage[1] else {
                throw Abort(.notFound, reason: "Aperçu non disponible.")
            }
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
            guard let record = await req.application.appState.preview(jobId: jobId),
                  let image = record.imagesByPage[page] else {
                throw Abort(.notFound, reason: "Page d'aperçu introuvable.")
            }
            return RangeResponse.make(req: req, data: image, contentType: .jpeg)
        }

        preview.get(":id", "page", ":n", use: pageHandler)

        preview.get(":id", "text") { req async throws -> PreviewTextResponse in
            guard let id = req.parameters.get("id"),
                  let jobId = UUID(uuidString: id) else {
                throw Abort(.badRequest, reason: "Identifiant d'aperçu invalide.")
            }
            guard let record = await req.application.appState.preview(jobId: jobId) else {
                throw Abort(.notFound, reason: "Aperçu non disponible.")
            }
            let page = (try? req.query.get(Int.self, at: "page")) ?? 1
            guard page > 0 else {
                throw Abort(.badRequest, reason: "Parametre page invalide.")
            }
            guard let text = record.textPages[page] else {
                throw Abort(.notFound, reason: "Texte d'aperçu introuvable pour cette page.")
            }
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
