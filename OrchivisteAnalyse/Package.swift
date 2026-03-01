// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrchivisteAnalyse",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OrchivisteAnalyse", targets: ["OrchivisteAnalyse"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.86.0")
    ],
    targets: [
        .executableTarget(
            name: "OrchivisteAnalyse",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        .testTarget(
            name: "OrchivisteAnalyseTests",
            dependencies: ["OrchivisteAnalyse"]
        )
    ]
)
