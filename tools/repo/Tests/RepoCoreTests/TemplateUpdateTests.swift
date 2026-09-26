import Foundation
import Testing

@testable import RepoCore

/// Two real git repositories in a temporary directory: a template with editions v0.1.0 and v0.2.0,
/// and a customer repository created from v0.1.0 the way "Use this template" would.
struct TemplateFixture {
    let base: URL
    let template: URL
    let customer: URL

    static let templatePaths = ["template.json", "tools", "docs", "AGENTS.md", "CLAUDE.md", "README.md", "repo.json"]
    static let customerPaths = templatePaths + ["apps"]

    static let customerAgents = """
        <!-- template:begin -->
        rules v1
        <!-- template:end -->

        ## 이 저장소의 규칙

        - customer rule
        """

    init() throws {
        base = try TestSupport.makeTemporaryDirectory()
        template = base.appending(path: "template", directoryHint: .isDirectory)
        customer = base.appending(path: "customer", directoryHint: .isDirectory)

        try git(["init", "--quiet", "-b", "main", template.path], in: base)
        try write(
            #"{"version": "0.1.0", "managedPaths": ["template.json", "tools/repo", "CLAUDE.md", "docs/decisions/README.md"], "managedBlocks": ["AGENTS.md"]}"#,
            "template.json",
            in: template
        )
        try write("main v1\n", "tools/repo/main.txt", in: template)
        try write("old\n", "tools/repo/old.txt", in: template)
        try write("record format\n", "docs/decisions/README.md", in: template)
        try write(
            "<!-- template:begin -->\nrules v1\n<!-- template:end -->\n\n## 이 저장소의 규칙\n",
            "AGENTS.md",
            in: template
        )
        try FileManager.default.createSymbolicLink(
            atPath: template.appending(path: "CLAUDE.md").path,
            withDestinationPath: "AGENTS.md"
        )
        try write("template readme v1\n", "README.md", in: template)
        try write(#"{"bundlePrefix": "com.example", "templateSource": ""}"#, "repo.json", in: template)
        try commit(Self.templatePaths, "v0.1.0", in: template)
        try git(["tag", "v0.1.0"], in: template)

        try git(["clone", "--quiet", "--branch", "v0.1.0", template.path, customer.path], in: base)
        try FileManager.default.removeItem(at: customer.appending(path: ".git"))
        try git(["init", "--quiet", "-b", "main"], in: customer)
        try write(Self.customerAgents, "AGENTS.md", in: customer)
        try write("mine\n", "apps/notes/VERSION", in: customer)
        try commit(Self.customerPaths, "Start from template", in: customer)

        try write(
            #"{"version": "0.2.0", "managedPaths": ["template.json", "tools/repo", "CLAUDE.md"], "managedBlocks": ["AGENTS.md"]}"#,
            "template.json",
            in: template
        )
        try write("main v2\n", "tools/repo/main.txt", in: template)
        try write("new\n", "tools/repo/new.txt", in: template)
        try FileManager.default.removeItem(at: template.appending(path: "tools/repo/old.txt"))
        try FileManager.default.removeItem(at: template.appending(path: "docs/decisions/README.md"))
        try write(
            "<!-- template:begin -->\nrules v2\n<!-- template:end -->\n\n## 이 저장소의 규칙\n",
            "AGENTS.md",
            in: template
        )
        try write("template readme v2\n", "README.md", in: template)
        try commit(Self.templatePaths, "v0.2.0", in: template)
        try git(["tag", "v0.2.0"], in: template)
    }

    var tasks: TemplateTasks {
        TemplateTasks(repository: Repository(root: customer), workingDirectory: customer)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: base)
    }

    @discardableResult
    func git(_ arguments: [String], in directory: URL) throws -> String {
        let settings = [
            "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
            "-c", "tag.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        ]
        return try Git.output(settings + arguments, in: directory)
    }

    func commit(_ paths: [String], _ message: String, in directory: URL) throws {
        try git(["add", "--"] + paths, in: directory)
        try git(["commit", "--quiet", "-m", message], in: directory)
    }

    func write(_ text: String, _ path: String, in directory: URL) throws {
        try TestSupport.write(text, to: directory.appending(path: path))
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: customer.appending(path: path), encoding: .utf8)
    }

    func customerStatus() throws -> String {
        try git(["status", "--porcelain", "--untracked-files=all"], in: customer)
    }
}

struct TemplateUpdateTests {
    @Test func statusShowsCurrentAndLatest() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }

        let status = try fixture.tasks.status(from: fixture.template.path)

        #expect(status.current == "0.1.0")
        #expect(status.versions == ["0.1.0", "0.2.0"])
        #expect(status.latest == "0.2.0")
        #expect(status.updateAvailable)
    }

    @Test func dryRunListsChangesAndWritesNothing() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }

        let outcome = try fixture.tasks.update(to: nil, from: fixture.template.path, dryRun: true)

        guard case .planned(let plan) = outcome else {
            Issue.record("expected a plan, got \(outcome)")
            return
        }
        #expect(plan.current.version == "0.1.0")
        #expect(plan.target.version == "0.2.0")
        #expect(
            plan.changes == [
                TemplateChange(.modified, "AGENTS.md"),
                TemplateChange(.deleted, "docs/decisions/README.md"),
                TemplateChange(.modified, "template.json"),
                TemplateChange(.modified, "tools/repo/main.txt"),
                TemplateChange(.added, "tools/repo/new.txt"),
                TemplateChange(.deleted, "tools/repo/old.txt"),
            ]
        )
        #expect(try fixture.customerStatus().isEmpty)
        #expect(fixture.read("tools/repo/main.txt") == "main v1\n")
    }

    @Test func updateReplacesManagedPartsOnly() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }

        let outcome = try fixture.tasks.update(to: nil, from: fixture.template.path, dryRun: false)

        guard case .applied(let plan, let changedPaths) = outcome else {
            Issue.record("expected an applied update, got \(outcome)")
            return
        }
        #expect(plan.target.version == "0.2.0")
        #expect(
            Set(changedPaths) == [
                "AGENTS.md", "docs/decisions/README.md", "template.json", "tools/repo/main.txt",
                "tools/repo/new.txt", "tools/repo/old.txt",
            ]
        )
        #expect(try TemplateManifest.load(from: fixture.customer).version == "0.2.0")
        #expect(fixture.read("tools/repo/main.txt") == "main v2\n")
        #expect(fixture.read("tools/repo/new.txt") == "new\n")
        #expect(fixture.read("tools/repo/old.txt") == nil)
        #expect(fixture.read("docs/decisions/README.md") == nil)
        #expect(
            fixture.read("AGENTS.md") == TemplateFixture.customerAgents.replacingOccurrences(of: "v1", with: "v2")
        )
        #expect(fixture.read("apps/notes/VERSION") == "mine\n")
        #expect(fixture.read("README.md") == "template readme v1\n")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: fixture.customer.appending(path: "CLAUDE.md").path
            ) == "AGENTS.md"
        )

        try fixture.commit(TemplateFixture.customerPaths, "Update template to 0.2.0", in: fixture.customer)
        let again = try fixture.tasks.update(to: nil, from: fixture.template.path, dryRun: false)
        guard case .upToDate("0.2.0") = again else {
            Issue.record("expected up to date, got \(again)")
            return
        }
    }

    @Test func refusesUncommittedChangesInManagedPaths() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }
        try fixture.write("local edit\n", "tools/repo/main.txt", in: fixture.customer)

        #expect(throws: RepoError.self) {
            try fixture.tasks.update(to: nil, from: fixture.template.path, dryRun: false)
        }
        #expect(fixture.read("tools/repo/main.txt") == "local edit\n")
        #expect(try TemplateManifest.load(from: fixture.customer).version == "0.1.0")
        #expect(fixture.read("tools/repo/old.txt") == "old\n")
    }

    @Test func refusesBlockFileWithoutMarkers() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }
        try fixture.write("no markers\n", "AGENTS.md", in: fixture.customer)
        try fixture.commit(["AGENTS.md"], "Drop markers", in: fixture.customer)

        #expect(throws: RepoError.self) {
            try fixture.tasks.update(to: nil, from: fixture.template.path, dryRun: false)
        }
        #expect(try fixture.customerStatus().isEmpty)
    }

    @Test func dryRunOnSameEditionFindsCommittedEdits() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }
        try fixture.write("edited in place\n", "tools/repo/main.txt", in: fixture.customer)
        try fixture.commit(["tools/repo/main.txt"], "Edit managed file", in: fixture.customer)

        let outcome = try fixture.tasks.update(to: "0.1.0", from: fixture.template.path, dryRun: true)

        guard case .planned(let plan) = outcome else {
            Issue.record("expected a plan, got \(outcome)")
            return
        }
        #expect(plan.changes == [TemplateChange(.modified, "tools/repo/main.txt")])
    }

    @Test func refusesTagThatDisagreesWithManifest() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }
        try fixture.git(["tag", "v0.3.0"], in: fixture.template)

        let error = #expect(throws: RepoError.self) {
            try fixture.tasks.update(to: "0.3.0", from: fixture.template.path, dryRun: false)
        }
        #expect(error?.message.contains("태그와 template.json 버전이 다릅니다") == true)
        #expect(try fixture.customerStatus().isEmpty)
    }

    @Test func refusesUnknownEdition() throws {
        let fixture = try TemplateFixture()
        defer { fixture.cleanUp() }

        #expect(throws: RepoError.self) {
            try fixture.tasks.update(to: "9.9.9", from: fixture.template.path, dryRun: true)
        }
        let usage = #expect(throws: RepoError.self) {
            try fixture.tasks.update(to: "latest", from: fixture.template.path, dryRun: true)
        }
        #expect(usage?.exitCode == ExitCode.usage)
    }
}
