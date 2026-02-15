import Fluent
import Vapor

enum EventPublisher {
    static func publish(
        type: String,
        payload: [String: String],
        application: Application,
        database: Database,
        logger: Logger
    ) async {
        do {
            let event = try await JobPersistenceRepository.appendEvent(
                type: type,
                payload: payload,
                on: database
            )
            await WebhookDispatcher.dispatch(event: event, application: application, logger: logger)
        } catch {
            logger.warning("Impossible de persister l'evenement.", metadata: [
                "event_type": .string(type),
                "error": .string(error.localizedDescription)
            ])
            await application.appState.addEvent(type: type, payload: payload)
        }
    }
}
