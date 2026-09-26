import Foundation
import Testing

@testable import RepoCore

/// A small template checkout (the source) and an existing git repository to adopt it into (the target).
struct AdoptFixture {
    let base: URL
    let template: URL
    let target: URL

    static let templateAgents = """
        <!-- template:begin -->
        template rules
        <!-- template:end -->

        ## 이 저장소의 규칙

        이 저장소에만 해당하는 규칙은 이 아래에 적습니다.

        """

    init() throws {
        base = try TestSupport.makeTemporaryDirectory()
        template = base.appending(path: "template", directoryHint: .isDirectory)
        target = base.appending(path: "target", directoryHint: .isDirectory)

        try write(
            #"{"version": "0.3.0", "managedPaths": ["template.json", "tools/repo", "CLAUDE.md"], "managedBlocks": ["AGENTS.md"]}"#,
            "template.json",
            in: template
        )
        try write("tool\n", "tools/repo/main.txt", in: template)
        try write(Self.templateAgents, "AGENTS.md", in: template)
        try FileManager.default.createSymbolicLink(
            atPath: template.appending(path: "CLAUDE.md").path,
            withDestinationPath: "AGENTS.md"
        )
        try write(
            #"{"bundlePrefix": "com.example", "templateSource": "https://example.com/template.git", "tenants": {}}"#,
            "repo.json",
            in: template
        )
        try write(".build/\n.swiftpm/\n.DS_Store\n", ".gitignore", in: template)
        try write("template readme\n", "README.md", in: template)

        try git(["init", "--quiet", "-b", "main", target.path], in: base)
        try write("my readme\n", "README.md", in: target)
        try write("apps\n", "apps/mine/main.txt", in: target)
        try commitAll("start")
    }

    var tasks: TemplateTasks {
        TemplateTasks(repository: Repository(root: template), workingDirectory: base)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: base)
    }

    @discardableResult
    func git(_ arguments: [String], in directory: URL) throws -> String {
        let settings = [
            "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
            "-c", "core.hooksPath=/dev/null",
        ]
        return try Git.output(settings + arguments, in: directory)
    }

    func commitAll(_ message: String) throws {
        let paths = try Git.changedPaths(["."], in: target)
        try git(["add", "--"] + paths, in: target)
        try git(["commit", "--quiet", "-m", message], in: target)
    }

    func write(_ text: String, _ path: String, in directory: URL) throws {
        try TestSupport.write(text, to: directory.appending(path: path))
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: target.appending(path: path), encoding: .utf8)
    }
}

struct AdoptTests {
    @Test func adoptsIntoARepositoryWithoutRulesDocuments() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }

        let outcome = try fixture.tasks.adopt(target: "target", bundlePrefix: "net.example", dryRun: false)

        guard case .applied(let plan, _, let changedPaths) = outcome else {
            Issue.record("expected an applied adoption, got \(outcome)")
            return
        }
        #expect(plan.version == "0.3.0")
        #expect(plan.movedOwnerContent.isEmpty)
        #expect(fixture.read("tools/repo/main.txt") == "tool\n")
        #expect(fixture.read("AGENTS.md") == AdoptFixture.templateAgents)
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: fixture.target.appending(path: "CLAUDE.md").path
            ) == "AGENTS.md"
        )
        let config = try Repository(root: fixture.target).loadConfig()
        #expect(config.bundlePrefix == "net.example")
        #expect(config.templateSource == "https://example.com/template.git")
        #expect(config.tenants == [:])
        #expect(fixture.read(".gitignore") == ".build/\n.swiftpm/\n.DS_Store\n")
        #expect(fixture.read("README.md") == "my readme\n")
        #expect(fixture.read("apps/mine/main.txt") == "apps\n")
        #expect(Set(changedPaths).isSuperset(of: ["template.json", "AGENTS.md", "repo.json", ".gitignore"]))
    }

    @Test func movesExistingRulesBelowTheOwnerSection() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        try fixture.write("# Old rules\n\n- keep this\n", "AGENTS.md", in: fixture.target)
        try fixture.write(".build/\n.worktrees/\n", ".gitignore", in: fixture.target)
        try fixture.write(#"{"bundlePrefix": "org.mine"}"#, "repo.json", in: fixture.target)
        try fixture.commitAll("rules")

        let outcome = try fixture.tasks.adopt(target: fixture.target.path, bundlePrefix: nil, dryRun: false)

        guard case .applied(let plan, _, _) = outcome else {
            Issue.record("expected an applied adoption, got \(outcome)")
            return
        }
        #expect(plan.movedOwnerContent == ["AGENTS.md"])
        #expect(fixture.read("AGENTS.md") == AdoptFixture.templateAgents + "\n# Old rules\n\n- keep this\n")
        #expect(fixture.read(".gitignore") == ".build/\n.worktrees/\n.swiftpm/\n.DS_Store\n")
        #expect(fixture.read("repo.json") == #"{"bundlePrefix": "org.mine"}"#)
    }

    @Test func refusesDifferentContentInManagedPaths() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        try fixture.write("my own tool\n", "tools/repo/main.txt", in: fixture.target)
        try fixture.write("extra\n", "tools/repo/extra.txt", in: fixture.target)
        try fixture.commitAll("tools")

        let error = #expect(throws: RepoError.self) {
            try fixture.tasks.adopt(target: fixture.target.path, bundlePrefix: nil, dryRun: false)
        }
        #expect(error?.message.contains("tools/repo/main.txt") == true)
        #expect(error?.message.contains("tools/repo/extra.txt") == true)
        #expect(!FileTree.itemExists(fixture.target.appending(path: "template.json")))
    }

    @Test func skipsManagedPathsWithEqualContent() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        try fixture.write("tool\n", "tools/repo/main.txt", in: fixture.target)
        try fixture.commitAll("same tool")

        let outcome = try fixture.tasks.adopt(target: fixture.target.path, bundlePrefix: nil, dryRun: true)

        guard case .planned(let plan) = outcome else {
            Issue.record("expected a plan, got \(outcome)")
            return
        }
        #expect(!plan.changes.contains { $0.path.hasPrefix("tools/") })
        #expect(plan.changes.contains(TemplateChange(.added, "template.json")))
    }

    @Test func refusesARepositoryThatAlreadyAdopted() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        _ = try fixture.tasks.adopt(target: fixture.target.path, bundlePrefix: nil, dryRun: false)
        try fixture.commitAll("adopt")

        let error = #expect(throws: RepoError.self) {
            try fixture.tasks.adopt(target: fixture.target.path, bundlePrefix: nil, dryRun: false)
        }
        #expect(error?.message.contains("template update") == true)
    }

    @Test func refusesUncommittedChanges() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        try fixture.write("draft\n", "notes.txt", in: fixture.target)

        #expect(throws: RepoError.self) {
            try fixture.tasks.adopt(target: fixture.target.path, bundlePrefix: nil, dryRun: true)
        }
        #expect(!FileTree.itemExists(fixture.target.appending(path: "template.json")))
    }

    @Test func dryRunWritesNothing() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }

        let outcome = try fixture.tasks.adopt(target: fixture.target.path, bundlePrefix: nil, dryRun: true)

        guard case .planned(let plan) = outcome else {
            Issue.record("expected a plan, got \(outcome)")
            return
        }
        #expect(
            plan.changes.map(\.path) == [
                ".gitignore", "AGENTS.md", "CLAUDE.md", "repo.json", "template.json", "tools/repo/main.txt",
            ]
        )
        #expect(try Git.changedPaths(["."], in: fixture.target).isEmpty)
    }

    @Test func refusesATargetThatIsNotAGitRepository() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        let plain = fixture.base.appending(path: "plain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        #expect(throws: RepoError.self) {
            try fixture.tasks.adopt(target: plain.path, bundlePrefix: nil, dryRun: true)
        }
    }
}

struct AdoptedRepositoryChecksTests {
    @Test func contextFilesFollowWhatGitSees() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        let target = fixture.target
        try fixture.write(".worktrees/\n", ".gitignore", in: target)
        try fixture.write("rules\n", "apps/mine/AGENTS.md", in: target)
        try fixture.commitAll("nested rules")
        try fixture.write("other checkout\n", ".worktrees/branch/AGENTS.md", in: target)
        try fixture.write("untracked\n", "docs/CLAUDE.md", in: target)

        #expect(DocumentChecks.misplacedContextFiles(in: target) == ["apps/mine/AGENTS.md", "docs/CLAUDE.md"])
    }

    @Test func pathDependenciesMustStayInPackages() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        func manifest(_ paths: [String]) -> String {
            "let package = Package(dependencies: [\(paths.map { ".package(path: \"\($0)\")" }.joined(separator: ", "))])"
        }
        try TestSupport.write(
            manifest(["../../packages/greeting"]), to: root.appending(path: "apps/good/Package.swift"))
        try TestSupport.write(manifest(["../shared"]), to: root.appending(path: "packages/greeting/Package.swift"))
        try TestSupport.write(manifest([]), to: root.appending(path: "packages/shared/Package.swift"))
        #expect(DependencyChecks.problems(in: root).isEmpty)

        try TestSupport.write(manifest(["../../../outside"]), to: root.appending(path: "apps/escape/Package.swift"))
        try TestSupport.write(manifest(["../good"]), to: root.appending(path: "apps/sibling/Package.swift"))
        try TestSupport.write(manifest(["../../packages/missing"]), to: root.appending(path: "apps/lost/Package.swift"))
        try TestSupport.write(
            manifest(["../../bricks/acme/packages/x"]),
            to: root.appending(path: "apps/brick/Package.swift")
        )

        let problems = DependencyChecks.problems(in: root)

        #expect(problems.count == 4)
        #expect(problems.contains { $0.hasPrefix("apps/escape ") })
        #expect(problems.contains { $0.hasPrefix("apps/sibling ") })
        #expect(problems.contains { $0.hasPrefix("apps/lost ") && $0.contains("packages/missing") })
        #expect(problems.contains { $0.hasPrefix("apps/brick ") })
    }

    @Test func executableProductComesFromInfoPlist() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "memo-board", directoryHint: .isDirectory)
        #expect(AppStructure.executableProduct(appDirectory: app, slug: "memo-board") == "MemoBoardApp")

        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>CFBundleExecutable</key><string>MemoBoard</string></dict></plist>
            """
        try TestSupport.write(plist, to: app.appending(path: "Packaging/Info.plist"))

        #expect(AppStructure.executableProduct(appDirectory: app, slug: "memo-board") == "MemoBoard")
    }
}
