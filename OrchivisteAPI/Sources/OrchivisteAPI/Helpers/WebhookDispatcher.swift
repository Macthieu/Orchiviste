import Foundation
import Vapor

enum WebhookDispatcher {
    static func dispatch(event: EventRecord, application: Application, logger: Logger) async {
        guard let webhookURL = Environment.get("ORCHIVISTE_WEBHOOK_URL"),
              !webhookURL.isEmpty,
              let secret = Environment.get("ORCHIVISTE_WEBHOOK_SECRET"),
              !secret.isEmpty else {
            return
        }

        let retries = max(1, Environment.get("ORCHIVISTE_WEBHOOK_MAX_RETRIES").flatMap(Int.init) ?? 3)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        guard let body = try? JSONEncoder().encode(event) else {
            logger.warning("Unable to encode webhook payload.", metadata: [
                "event_type": .string(event.type),
                "event_id": .string("\(event.id)")
            ])
            return
        }
        let signature = WebhookSignature.sign(secret: secret, timestamp: timestamp, body: body)

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "application/json")
        headers.replaceOrAdd(name: "x-orchiviste-timestamp", value: timestamp)
        headers.replaceOrAdd(name: "x-orchiviste-signature", value: "sha256=\(signature)")
        headers.replaceOrAdd(name: "x-orchiviste-event-type", value: event.type)
        headers.replaceOrAdd(name: "x-orchiviste-event-id", value: "\(event.id)")

        for attempt in 1...retries {
            do {
                let response = try await application.client.post(URI(string: webhookURL), headers: headers) { req in
                    req.body = .init(data: body)
                }
                if response.status.code >= 200, response.status.code < 300 {
                    return
                }
                throw Abort(.badGateway, reason: "Webhook receiver returned \(response.status.code).")
            } catch {
                if attempt == retries {
                    logger.error("Webhook delivery failed.", metadata: [
                        "event_id": .string("\(event.id)"),
                        "event_type": .string(event.type),
                        "error": .string(error.localizedDescription)
                    ])
                    return
                }
                let backoffMillis = UInt64(250 * attempt)
                try? await Task.sleep(nanoseconds: backoffMillis * 1_000_000)
            }
        }
    }
}
