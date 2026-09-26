// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "repo",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "repo", targets: ["repo"])
    ],
    targets: [
        .target(
            name: "RepoCore",
            path: "tools/repo/Sources/RepoCore"
        ),
        .executableTarget(
            name: "repo",
            dependencies: ["RepoCore"],
            path: "tools/repo/Sources/repo"
        ),
        .testTarget(
            name: "RepoCoreTests",
            dependencies: ["RepoCore"],
            path: "tools/repo/Tests/RepoCoreTests"
        ),
    ]
)
