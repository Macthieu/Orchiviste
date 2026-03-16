// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrchivisteAnalyse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrchivisteAnalyseCore", targets: ["OrchivisteAnalyseCore"]),
        .executable(name: "OrchivisteAnalyse", targets: ["OrchivisteAnalyse"])
    ],
    dependencies: [
        .package(path: "../OrchivisteSharedKit"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.86.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "OrchivisteAnalyseCore",
            dependencies: [
                .product(name: "OrchivisteSharedKit", package: "OrchivisteSharedKit"),
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .executableTarget(
            name: "OrchivisteAnalyse",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "OrchivisteAnalyseCore"
            ]
        ),
        .testTarget(
            name: "OrchivisteAnalyseTests",
            dependencies: [
                "OrchivisteAnalyse",
                "OrchivisteAnalyseCore",
                .product(name: "OrchivisteSharedKit", package: "OrchivisteSharedKit")
            ]
        )
    ]
)
