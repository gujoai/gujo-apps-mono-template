// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "__NAME__",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "__NAME__App", targets: ["__NAME__App"]),
        .executable(name: "__name__", targets: ["__NAME__CLI"]),
    ],
    targets: [
        .target(name: "__NAME__Core"),
        .executableTarget(name: "__NAME__App", dependencies: ["__NAME__Core"]),
        .executableTarget(name: "__NAME__CLI", dependencies: ["__NAME__Core"]),
        .testTarget(name: "__NAME__CoreTests", dependencies: ["__NAME__Core"]),
    ]
)
