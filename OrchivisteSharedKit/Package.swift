// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrchivisteSharedKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "OrchivisteSharedKit", targets: ["OrchivisteSharedKit"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")],
    targets: [.target(name: "OrchivisteSharedKit", dependencies: ["Yams"])]
)
