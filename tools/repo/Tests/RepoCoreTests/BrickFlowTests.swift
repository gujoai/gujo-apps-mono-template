import Foundation
import Testing

@testable import RepoCore

/// Real git repositories in a temporary directory: tenants `a` and `b`, made from this template, and an
/// owner's repository that registers both. Tenant `a` is registered by absolute path, `b` by relative path.
struct BrickFixture {
    let base: URL
    let tenantA: URL
    let tenantB: URL
    let owner: URL

    init() throws {
        base = try TestSupport.makeTemporaryDirectory()
        tenantA = base.appending(path: "tenant-a", directoryHint: .isDirectory)
        tenantB = base.appending(path: "tenant-b", directoryHint: .isDirectory)
        owner = base.appending(path: "owner", directoryHint: .isDirectory)

        try makeTenant(tenantA, apps: ["notes": ["greeting"]], packages: ["greeting": []])
        try write("tenant rules\n", "apps/notes/AGENTS.md", in: tenantA)
        try commitAll(tenantA, "a 1.0.0")
        try git(["tag", "v1.0.0"], in: tenantA)

        try makeTenant(tenantB, apps: ["notes": [], "todo": ["shared"]], packages: ["shared": ["util"], "util": []])
        try commitAll(tenantB, "b 0.1.0")
        try git(["tag", "v0.1.0"], in: tenantB)

        try git(["init", "--quiet", "-b", "main", owner.path], in: base)
        try write(
            #"{"bundlePrefix": "com.example", "tenants": {"a": "\#(tenantA.path)", "b": "../tenant-b"}}"#,
            "repo.json",
            in: owner
        )
        try commitAll(owner, "owner")
    }

    var tasks: BrickTasks {
        BrickTasks(repository: Repository(root: owner))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: base)
    }

    func makeTenant(_ root: URL, apps: [String: [String]], packages: [String: [String]]) throws {
        try git(["init", "--quiet", "-b", "main", root.path], in: base)
        try write(
            #"{"version": "0.1.0", "managedPaths": ["template.json"], "managedBlocks": []}"#, "template.json", in: root)
        for (app, dependencies) in apps {
            let lines = dependencies.map { ".package(path: \"../../packages/\($0)\")" }.joined(separator: ",\n        ")
            try write(
                "let package = Package(\n    name: \"\(app)\",\n    dependencies: [\n        \(lines)\n    ]\n)\n",
                "apps/\(app)/Package.swift",
                in: root
            )
            try write("0.1.0\n", "apps/\(app)/VERSION", in: root)
            try write("let \(app) = 1\n", "apps/\(app)/Sources/Core/Core.swift", in: root)
        }
        for (package, dependencies) in packages {
            let lines = dependencies.map { ".package(path: \"../\($0)\")" }.joined(separator: ", ")
            try write(
                "let package = Package(name: \"\(package)\", dependencies: [\(lines)])\n",
                "packages/\(package)/Package.swift",
                in: root
            )
            try write("let \(package) = 1\n", "packages/\(package)/Sources/Lib/Lib.swift", in: root)
        }
    }

    @discardableResult
    func git(_ arguments: [String], in directory: URL) throws -> String {
        let settings = [
            "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
            "-c", "tag.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        ]
        return try Git.output(settings + arguments, in: directory)
    }

    /// Commits every changed path, each named explicitly.
    func commitAll(_ directory: URL, _ message: String) throws {
        let paths = try Git.changedPaths(["."], in: directory)
        try git(["add", "--"] + paths, in: directory)
        try git(["commit", "--quiet", "-m", message], in: directory)
    }

    func write(_ text: String, _ path: String, in directory: URL) throws {
        try TestSupport.write(text, to: directory.appending(path: path))
    }

    func ownerFile(_ path: String) -> String? {
        try? String(contentsOf: owner.appending(path: path), encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        FileTree.itemExists(owner.appending(path: path))
    }

    func ownerStatus() throws -> [String] {
        try Git.changedPaths(["."], in: owner)
    }

    func tagCommit(_ tag: String, in directory: URL) throws -> String {
        try git(["rev-parse", "\(tag)^{commit}"], in: directory).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func lock() throws -> BrickLock {
        try BrickLock.load(from: owner)
    }
}

struct BrickFlowTests {
    let a = "a"
    let b = "b"

    @Test func addTakesTheAppWithItsPackages() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }

        let result = try fixture.tasks.add(AppRef(tenant: a, slug: "notes"), edition: nil)

        #expect(fixture.exists("bricks/a/apps/notes/Package.swift"))
        #expect(fixture.exists("bricks/a/packages/greeting/Sources/Lib/Lib.swift"))
        #expect(!fixture.exists("bricks/a/apps/notes/AGENTS.md"))
        #expect(result.skippedContextFiles == ["bricks/a/apps/notes/AGENTS.md"])
        let entry = try #require(try fixture.lock().tenants[a])
        #expect(entry.edition == "1.0.0")
        #expect(entry.commit == (try fixture.tagCommit("v1.0.0", in: fixture.tenantA)))
        #expect(entry.apps == ["notes"])
        #expect(entry.packages == ["greeting"])
        #expect(entry.source == fixture.tenantA.path)
        #expect(result.changedPaths.contains("bricks.lock"))
    }

    @Test func sameAppNameFromTwoTenantsAndRecursivePackages() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }

        try fixture.tasks.add(AppRef(tenant: a, slug: "notes"), edition: nil)
        try fixture.tasks.add(AppRef(tenant: b, slug: "notes"), edition: nil)
        try fixture.tasks.add(AppRef(tenant: b, slug: "todo"), edition: nil)

        #expect(fixture.exists("bricks/a/apps/notes") && fixture.exists("bricks/b/apps/notes"))
        #expect(try fixture.lock().tenants[b]?.packages == ["shared", "util"])
        #expect(try fixture.lock().tenants[b]?.source == "../tenant-b")
        #expect(Repository(root: fixture.owner).brickApps().map(\.description) == ["a/notes", "b/notes", "b/todo"])
    }

    @Test func unregisteredTenantIsRefused() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }

        let error = #expect(throws: RepoError.self) {
            try fixture.tasks.add(AppRef(tenant: "x", slug: "notes"), edition: nil)
        }
        #expect(error?.exitCode == ExitCode.failure)
        #expect(error?.message.contains("repo.json 의 tenants") == true)
        #expect(!fixture.exists("bricks"))
    }

    @Test func oneEditionPerTenant() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }
        try fixture.write("let todo = 2\n", "apps/todo/Sources/Core/Core.swift", in: fixture.tenantB)
        try fixture.commitAll(fixture.tenantB, "b 0.2.0")
        try fixture.git(["tag", "v0.2.0"], in: fixture.tenantB)
        try fixture.tasks.add(AppRef(tenant: b, slug: "notes"), edition: "0.1.0")

        #expect(throws: RepoError.self) {
            try fixture.tasks.add(AppRef(tenant: b, slug: "todo"), edition: "0.2.0")
        }
        try fixture.tasks.add(AppRef(tenant: b, slug: "todo"), edition: nil)
        #expect(try fixture.lock().tenants[b]?.edition == "0.1.0")
        #expect(fixture.ownerFile("bricks/b/apps/todo/Sources/Core/Core.swift") == "let todo = 1\n")
    }

    @Test func updateShowsChangesThenReplacesTheBricks() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }
        try fixture.tasks.add(AppRef(tenant: a, slug: "notes"), edition: nil)
        try fixture.commitAll(fixture.owner, "add a/notes")
        try fixture.write("let notes = 2\n", "apps/notes/Sources/Core/Core.swift", in: fixture.tenantA)
        try fixture.write("let greeting = 2\n", "packages/greeting/Sources/Lib/Lib.swift", in: fixture.tenantA)
        try fixture.commitAll(fixture.tenantA, "a 1.1.0")
        try fixture.git(["tag", "v1.1.0"], in: fixture.tenantA)

        let planned = try fixture.tasks.update(a, edition: nil, dryRun: true)

        guard case .planned(_, let from, let to, let changes) = planned else {
            Issue.record("expected a plan, got \(planned)")
            return
        }
        #expect(from == "1.0.0" && to == "1.1.0")
        #expect(
            changes == [
                TemplateChange(.modified, "bricks/a/apps/notes/Sources/Core/Core.swift"),
                TemplateChange(.modified, "bricks/a/packages/greeting/Sources/Lib/Lib.swift"),
            ]
        )
        #expect(try fixture.ownerStatus().isEmpty)

        let applied = try fixture.tasks.update(a, edition: nil, dryRun: false)

        guard case .applied(let result) = applied else {
            Issue.record("expected an applied update, got \(applied)")
            return
        }
        #expect(result.previousEdition == "1.0.0" && result.edition == "1.1.0")
        #expect(fixture.ownerFile("bricks/a/apps/notes/Sources/Core/Core.swift") == "let notes = 2\n")
        #expect(fixture.ownerFile("bricks/a/packages/greeting/Sources/Lib/Lib.swift") == "let greeting = 2\n")
        #expect(try fixture.lock().tenants[a]?.commit == (try fixture.tagCommit("v1.1.0", in: fixture.tenantA)))
        try fixture.commitAll(fixture.owner, "update a")
        guard case .upToDate = try fixture.tasks.update(a, edition: nil, dryRun: false) else {
            Issue.record("expected up to date")
            return
        }
    }

    @Test func movedTagIsRefused() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }
        try fixture.tasks.add(AppRef(tenant: a, slug: "notes"), edition: nil)
        try fixture.commitAll(fixture.owner, "add a/notes")
        try fixture.write("let notes = 3\n", "apps/notes/Sources/Core/Core.swift", in: fixture.tenantA)
        try fixture.commitAll(fixture.tenantA, "moved")
        try fixture.git(["tag", "-f", "v1.0.0"], in: fixture.tenantA)

        let error = #expect(throws: RepoError.self) {
            try fixture.tasks.update(a, edition: "1.0.0", dryRun: false)
        }
        #expect(error?.message.contains("태그를 옮겼습니다") == true)
        #expect(fixture.ownerFile("bricks/a/apps/notes/Sources/Core/Core.swift") == "let notes = 1\n")
    }

    @Test func uncommittedBrickChangesAreRefusedAndCommittedOnesShow() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }
        try fixture.tasks.add(AppRef(tenant: a, slug: "notes"), edition: nil)
        try fixture.commitAll(fixture.owner, "add a/notes")
        try fixture.write("let notes = 9\n", "bricks/a/apps/notes/Sources/Core/Core.swift", in: fixture.owner)

        #expect(throws: RepoError.self) {
            try fixture.tasks.update(a, edition: nil, dryRun: true)
        }
        try fixture.commitAll(fixture.owner, "edit brick")
        let outcome = try fixture.tasks.update(a, edition: "1.0.0", dryRun: true)

        guard case .planned(_, _, _, let changes) = outcome else {
            Issue.record("expected a plan, got \(outcome)")
            return
        }
        #expect(changes == [TemplateChange(.modified, "bricks/a/apps/notes/Sources/Core/Core.swift")])
    }

    @Test func removeDropsUnusedPackagesAndTheEmptyTenant() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }
        try fixture.tasks.add(AppRef(tenant: b, slug: "notes"), edition: nil)
        try fixture.tasks.add(AppRef(tenant: b, slug: "todo"), edition: nil)
        try fixture.commitAll(fixture.owner, "add b")

        try fixture.tasks.remove(AppRef(tenant: b, slug: "todo"))

        #expect(!fixture.exists("bricks/b/apps/todo"))
        #expect(!fixture.exists("bricks/b/packages/shared") && !fixture.exists("bricks/b/packages/util"))
        #expect(try fixture.lock().tenants[b]?.apps == ["notes"])
        #expect(try fixture.lock().tenants[b]?.packages == [])
        try fixture.commitAll(fixture.owner, "remove b/todo")

        try fixture.tasks.remove(AppRef(tenant: b, slug: "notes"))

        #expect(!fixture.exists("bricks"))
        #expect(!fixture.exists(Tenants.lockFileName))
    }

    @Test func ejectMovesTheAppToTheOwnerArea() throws {
        let fixture = try BrickFixture()
        defer { fixture.cleanUp() }
        try fixture.tasks.add(AppRef(tenant: a, slug: "notes"), edition: nil)
        try fixture.tasks.add(AppRef(tenant: b, slug: "notes"), edition: nil)
        try fixture.commitAll(fixture.owner, "add")

        let result = try fixture.tasks.eject(AppRef(tenant: a, slug: "notes"))

        #expect(fixture.ownerFile("apps/notes/Sources/Core/Core.swift") == "let notes = 1\n")
        #expect(fixture.exists("packages/greeting/Package.swift"))
        #expect(!fixture.exists("bricks/a"))
        #expect(try fixture.lock().tenants[a] == nil)
        #expect(result.changedPaths.contains("apps/notes/Package.swift"))
        try fixture.commitAll(fixture.owner, "eject a/notes")

        let error = #expect(throws: RepoError.self) {
            try fixture.tasks.eject(AppRef(tenant: b, slug: "notes"))
        }
        #expect(error?.message.contains("apps/notes") == true)
        #expect(fixture.exists("bricks/b/apps/notes"))
    }
}
