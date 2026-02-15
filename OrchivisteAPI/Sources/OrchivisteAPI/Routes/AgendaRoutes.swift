import Vapor

func registerAgendaRoutes(_ app: Application) {
    app.group("v1") { v1 in
        v1.post("agenda", "import") { req async throws -> AgendaRecord in
            let agenda = try req.content.decode(AgendaRecord.self)
            await req.application.appState.saveAgenda(agenda)
            try ConfigLoader.saveAgenda(agenda)
            return agenda
        }

        v1.get("agenda", ":session_id") { req async throws -> AgendaRecord in
            guard let sessionId = req.parameters.get("session_id") else {
                throw Abort(.badRequest, reason: "session_id is required.")
            }
            if let stored = await req.application.appState.agenda(sessionId: sessionId) {
                return stored
            }
            if let disk = ConfigLoader.loadAgenda(sessionId: sessionId) {
                return disk
            }
            throw Abort(.notFound, reason: "Agenda not found.")
        }
    }
}
