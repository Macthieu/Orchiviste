import Vapor

func registerPreviewRoutes(_ app: Application) {
    app.group("v1", "preview") { preview in
        preview.get(":id", "thumbnail") { req async throws -> Response in
            guard let jobId = req.parameters.get("id").flatMap(UUID.init(uuidString:)),
                  let record = await req.application.appState.preview(jobId: jobId),
                  let image = record.imagesByPage[1] else {
                throw Abort(.notFound, reason: "Preview not ready.")
            }
            return RangeResponse.make(req: req, data: image, contentType: .jpeg)
        }

        let pageHandler: (Request) async throws -> Response = { req in
            guard let jobId = req.parameters.get("id").flatMap(UUID.init(uuidString:)),
                  let pageStr = req.parameters.get("n") ?? req.parameters.get("n.jpg"),
                  let page = Int(pageStr),
                  let record = await req.application.appState.preview(jobId: jobId),
                  let image = record.imagesByPage[page] else {
                throw Abort(.notFound, reason: "Preview page not found.")
            }
            return RangeResponse.make(req: req, data: image, contentType: .jpeg)
        }

        preview.get(":id", "page", ":n", use: pageHandler)
        preview.get(":id", "page", ":n.jpg", use: pageHandler)

        preview.get(":id", "text") { req async throws -> PreviewTextResponse in
            guard let jobId = req.parameters.get("id").flatMap(UUID.init(uuidString:)),
                  let record = await req.application.appState.preview(jobId: jobId) else {
                throw Abort(.notFound, reason: "Preview not ready.")
            }
            let page = (try? req.query.get(Int.self, at: "page")) ?? 1
            let text = record.textPages[page] ?? ""
            return PreviewTextResponse(page: page, text: text)
        }

        preview.get(":id", "office") { req async throws -> Response in
            guard let jobId = req.parameters.get("id").flatMap(UUID.init(uuidString:)),
                  let job = await req.application.appState.job(id: jobId) else {
                throw Abort(.notFound, reason: "Job not found.")
            }
            guard job.source.kind.lowercased() == "sharepoint",
                  let url = job.source.url else {
                throw Abort(.conflict, reason: "Office Online only available for SharePoint sources.")
            }
            return req.redirect(to: url)
        }
    }
}
