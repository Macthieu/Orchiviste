// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrchivisteWorker",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OrchivisteWorker", targets: ["OrchivisteWorker"])],
    dependencies: [
        .package(url: "https://github.com/Mordil/RediStack.git", revision: "a05d4bcf578430e8c5dbdae56cb6ac395cd806a0"),
        .package(path: "../OrchivisteSharedKit")
    ],
    targets: [
        .executableTarget(
            name: "OrchivisteWorker",
            dependencies: ["RediStack", "OrchivisteSharedKit"]
        )
    ]
)
