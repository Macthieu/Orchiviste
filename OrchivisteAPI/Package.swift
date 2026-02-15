// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrchivisteAPI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OrchivisteAPI", targets: ["OrchivisteAPI"])
    ],
    dependencies: [
        // Local shared kit (mono-repo)
        .package(path: "../OrchivisteSharedKit"),

        // Vapor stack
        .package(url: "https://github.com/vapor/vapor.git", from: "4.86.0"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.2.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.6.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.5.0"),

        // Other deps
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
        .package(url: "https://github.com/Mordil/RediStack.git", branch: "main"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OrchivisteAPI",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "RediStack", package: "RediStack"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "OrchivisteSharedKit", package: "OrchivisteSharedKit")
            ]
        ),
        .testTarget(
            name: "OrchivisteAPITests",
            dependencies: ["OrchivisteAPI"]
        )
    ]
)
