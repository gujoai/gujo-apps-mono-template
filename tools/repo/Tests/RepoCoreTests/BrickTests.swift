import Foundation
import Testing

@testable import RepoCore

struct PackageDependenciesTests {
    @Test func findsPathAndURLDependencies() {
        let manifest = """
            // swift-tools-version: 6.1

            import PackageDescription

            let package = Package(
                name: "Notes",
                dependencies: [
                    .package(path: "../../packages/greeting"),
                    .package(
                        name: "Shared",
                        path: "../../packages/shared"
                    ),
                    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
                    // .package(path: "../../packages/old"),
                ],
                targets: [
                    .target(name: "NotesCore", dependencies: [.product(name: "Greeting", package: "greeting")])
                ]
            )
            """

        let declared = PackageDependencies.declared(in: manifest)

        #expect(declared.paths == ["../../packages/greeting", "../../packages/shared"])
        #expect(declared.urls == ["https://github.com/apple/swift-collections.git"])
    }

    @Test func manifestWithoutDependencies() {
        #expect(PackageDependencies.declared(in: "let package = Package(name: \"A\")") == .init())
    }

    @Test(arguments: [
        ("../../packages/greeting", "apps/notes", "greeting"),
        ("./../../packages/greeting", "apps/notes", "greeting"),
        ("../greeting", "packages/shared", "greeting"),
    ])
    func resolvesPackagePaths(_ path: String, _ directory: String, _ expected: String) {
        #expect(PackageDependencies.packageName(resolving: path, from: directory) == expected)
    }

    @Test(arguments: [
        ("../../../outside", "apps/notes"),
        ("../todo", "apps/notes"),
        ("../../apps/todo", "apps/notes"),
        ("/Library/Shared", "apps/notes"),
        ("../../packages/greeting/Sources", "apps/notes"),
        ("../../packages/.hidden", "apps/notes"),
    ])
    func rejectsPathsOutsidePackages(_ path: String, _ directory: String) {
        #expect(PackageDependencies.packageName(resolving: path, from: directory) == nil)
    }

    func manifest(_ paths: [String]) -> String {
        "let package = Package(dependencies: [\(paths.map { ".package(path: \"\($0)\")" }.joined(separator: ", "))])"
    }

    @Test func followsPackagesRecursively() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestSupport.write(manifest(["../../packages/a"]), to: root.appending(path: "apps/notes/Package.swift"))
        try TestSupport.write(manifest(["../b", "../c"]), to: root.appending(path: "packages/a/Package.swift"))
        try TestSupport.write(manifest(["../c"]), to: root.appending(path: "packages/b/Package.swift"))
        try TestSupport.write(manifest(["../a"]), to: root.appending(path: "packages/c/Package.swift"))

        let closure = try PackageDependencies.closure(of: "apps/notes", in: root)

        #expect(closure.packages == ["a", "b", "c"])
    }

    @Test func refusesDependencyOnAnotherApp() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestSupport.write(manifest(["../todo"]), to: root.appending(path: "apps/notes/Package.swift"))

        #expect(throws: RepoError.self) {
            try PackageDependencies.closure(of: "apps/notes", in: root)
        }
    }
}

struct BrickLockTests {
    @Test func roundTripsWithSortedLists() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = BrickLock.Entry(
            source: "../tenant",
            edition: "1.0.0",
            commit: "abc",
            apps: ["todo", "notes"],
            packages: ["shared", "greeting", "shared"]
        )

        try BrickLock(tenants: ["acme": entry]).write(to: root)
        let loaded = try BrickLock.load(from: root)

        #expect(loaded.tenants["acme"]?.apps == ["notes", "todo"])
        #expect(loaded.tenants["acme"]?.packages == ["greeting", "shared"])
        #expect(loaded.tenants["acme"]?.commit == "abc")
    }

    @Test func missingLockIsEmptyAndEmptyLockIsDeleted() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try BrickLock.load(from: root).tenants.isEmpty)
        try TestSupport.write("{}", to: root.appending(path: Tenants.lockFileName))

        #expect(throws: RepoError.self) {
            try BrickLock.load(from: root)
        }
        try BrickLock().write(to: root)
        #expect(!FileTree.itemExists(root.appending(path: Tenants.lockFileName)))
    }

    @Test func parsesAppReferences() throws {
        #expect(try AppRef.parse("notes") == AppRef(slug: "notes"))
        #expect(try AppRef.parse("acme/notes") == AppRef(tenant: "acme", slug: "notes"))
        #expect(AppRef(tenant: "acme", slug: "notes").path == "bricks/acme/apps/notes")
        for invalid in ["Acme/notes", "acme/", "a/b/c", "/notes"] {
            #expect(throws: RepoError.self) {
                try AppRef.parse(invalid)
            }
        }
    }

    @Test func doctorFindsLockAndDirectoryMismatches() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bricks = root.appending(path: "bricks")
        try FileManager.default.createDirectory(
            at: bricks.appending(path: "acme/apps/notes"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bricks.appending(path: "other/apps/x"),
            withIntermediateDirectories: true
        )
        let lock = BrickLock(tenants: [
            "acme": .init(source: "s", edition: "1.0.0", commit: "c", apps: ["notes", "todo"], packages: ["greeting"])
        ])

        let problems = BrickChecks.mismatches(lock, bricksDirectory: bricks)

        #expect(
            problems == [
                "bricks/other/ 가 기록에 없음", "bricks/acme/apps/todo 없음", "bricks/acme/packages/greeting 없음",
            ]
        )
    }
}
