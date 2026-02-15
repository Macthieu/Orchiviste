import Vapor

func registerTaxonomyRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("taxonomy", "syged", "import") { req async throws -> TaxonomyRecord in
            let taxonomy = try req.content.decode(TaxonomyRecord.self)
            await req.application.appState.saveTaxonomy(taxonomy)
            try ConfigLoader.saveTaxonomy(taxonomy)
            return taxonomy
        }

        v1.get("taxonomy", ":taxonomy_id") { req async throws -> TaxonomyRecord in
            guard let id = req.parameters.get("taxonomy_id") else {
                throw Abort(.badRequest, reason: "taxonomy_id est requis.")
            }
            if let stored = await req.application.appState.taxonomy(id: id) {
                return stored
            }
            if let disk = ConfigLoader.loadTaxonomy(id: id) {
                return disk
            }
            throw Abort(.notFound, reason: "Taxonomie introuvable.")
        }
    }
}
