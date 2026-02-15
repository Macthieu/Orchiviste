import Foundation
import NIOCore
import NIOPosix
import RediStack
import OrchivisteSharedKit

@main
struct Worker {
    static func main() {
        let urlStr = ProcessInfo.processInfo.environment["ORCHIVISTE_REDIS_URL"] ?? "redis://127.0.0.1:6379"
        let url = URL(string: urlStr)!
        let host = url.host ?? "127.0.0.1"
        let port = url.port ?? 6379

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // ⬇️ nouvelle façon de construire le pool
        let address = try! SocketAddress.makeAddressResolvingHost(host, port: port)
        let pool = RedisConnectionPool(
            configuration: .init(
                initialServerConnectionAddresses: [address],
                maximumConnectionCount: .maximumActiveConnections(2),
                connectionFactoryConfiguration: .init()
            ),
            boundEventLoop: group.next()
        )
        pool.activate()

        let key = RedisKey("orchiviste:ingest")
        print("🧰 Agent demarre. En attente de taches sur \(host):\(port)…")

        while true {
            do {
                // ⬇️ .seconds(0) vient de NIOCore
                let popped = try pool.leaseConnection {
                    $0.blpop(from: key, timeout: TimeAmount.seconds(0))
                }.wait()

                guard let json = popped.string else { continue }
                let item = try JSONDecoder().decode(IngestJob.self, from: Data(json.utf8))

                let tags = item.tags ?? []
                print("📝 Traitement \(item.taskId) — \(item.fileURL) [\(item.source)] \(tags)")
                Thread.sleep(forTimeInterval: 1.0) // simulateur
                print("✅ Terminé \(item.taskId)")
            } catch {
                print("💥 Erreur worker: \(error)")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}
