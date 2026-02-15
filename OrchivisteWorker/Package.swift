// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrchivisteWorker",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OrchivisteWorker", targets: ["OrchivisteWorker"])],
    dependencies: [
        .package(url: "https://github.com/Mordil/RediStack.git", branch: "main"),
        .package(path: "../OrchivisteSharedKit")
    ],
    targets: [
        .executableTarget(
            name: "OrchivisteWorker",
            dependencies: ["RediStack", "OrchivisteSharedKit"]
        )
    ]
)
