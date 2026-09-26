import Foundation
import Testing

@testable import RepoCore

private let openA = "<!-- okf:derived id=a source=version -->"
private let close = "<!-- /okf:derived -->"

struct OKFTests {
    /// apps/notes uses packages/greeting (with traits) and packages/shared; packages/greeting uses shared.
    func makeRoot() throws -> URL {
        let root = try TestSupport.makeTemporaryDirectory()
        let files = [
            "apps/notes/README.md": "---\ntitle: \"Notes\"\ndescription: 메모 앱\n---\n# 메모\n\n본문\n",
            "apps/notes/VERSION": " 1.2.0\n",
            "apps/notes/Package.swift": """
            let package = Package(dependencies: [
                .package(path: "../../packages/shared"),
                // .package(path: "../../packages/old"),
                .package(path: "../../packages/greeting/", traits: ["Fancy", "Loud"]),
            ])
            """,
            "packages/greeting/README.md": "# Greeting\n",
            "packages/greeting/Package.swift": #"let package = Package(dependencies: [.package(path: "../shared")])"#,
            "packages/shared/README.md": "shared\n",
            "packages/shared/Package.swift": "let package = Package()",
        ]
        for (path, text) in files {
            try TestSupport.write(text, to: root.appending(path: path))
        }
        return root
    }

    func read(_ path: String, in root: URL) -> String? {
        try? String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test func generatorsMatchTheFirstGenerationFormat() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try OKF.generate("version", directory: "apps/notes", root: root) == "Version: 1.2.0")
        #expect(
            try OKF.generate("deps", directory: "apps/notes", root: root) == """
                ## Dependencies

                * [greeting](../../packages/greeting/README.md) (traits: Fancy, Loud)
                * [shared](../../packages/shared/README.md)
                """
        )
        #expect(
            try OKF.generate("deps", directory: "packages/shared", root: root) == "## Dependencies\n\n_none_"
        )
        #expect(
            try OKF.generate("used-by", directory: "packages/shared", root: root)
                == "## Used by\n\n* [notes](../../apps/notes/README.md)"
        )
        #expect(
            try OKF.generate("index", directory: "", root: root) == """
                ## Apps

                * [Notes](apps/notes/README.md) - 메모 앱

                ## Packages

                * [Greeting](packages/greeting/README.md)
                * [shared](packages/shared/README.md)
                """
        )
    }

    @Test func syncAppendsStandardBlocksAndCheckAgrees() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = OKF.plan(root: root)
        #expect(plan.problems.isEmpty)
        #expect(
            plan.writes.keys.sorted() == [
                "apps/notes/README.md", "index.md", "packages/greeting/README.md", "packages/shared/README.md",
            ]
        )
        try OKF.apply(plan, root: root)

        #expect(
            read("apps/notes/README.md", in: root)
                == "---\ntitle: \"Notes\"\ndescription: 메모 앱\n---\n# 메모\n\n본문\n\n"
                + "<!-- okf:derived id=version source=version -->\nVersion: 1.2.0\n<!-- /okf:derived -->\n\n"
                + "<!-- okf:derived id=deps source=deps -->\n## Dependencies\n\n"
                + "* [greeting](../../packages/greeting/README.md) (traits: Fancy, Loud)\n"
                + "* [shared](../../packages/shared/README.md)\n<!-- /okf:derived -->\n"
        )
        #expect(
            read("index.md", in: root)?.hasPrefix("# 앱과 패키지 목록\n\n<!-- okf:derived id=index source=index -->\n") == true
        )
        #expect(
            read("packages/greeting/README.md", in: root)?.contains("<!-- okf:derived id=used-by source=used-by -->")
                == true)
        #expect(OKF.plan(root: root).writes.isEmpty)

        try TestSupport.write("1.3.0\n", to: root.appending(path: "apps/notes/VERSION"))
        #expect(OKF.plan(root: root).writes.keys.sorted() == ["apps/notes/README.md"])
    }

    @Test func syncReplacesOnlyBlockContent() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let readme = """
            # Notes
            <!-- okf:block id=keep owner=authored -->
            사람이 쓴 글
            <!-- /okf:block -->
            <!-- okf:derived id=version source=version -->
            Version: 0.0.1\u{20}\u{20}
            <!-- /okf:derived -->
            ```
            <!-- okf:derived id=ignored source=nothing -->
            ```
            tail
            """
        try TestSupport.write(readme, to: root.appending(path: "apps/notes/README.md"))

        let (updated, problems) = OKF.sync(readme, document: "apps/notes/README.md", kind: .app, root: root)

        #expect(problems.isEmpty)
        #expect(
            updated?.hasPrefix(readme.replacingOccurrences(of: "Version: 0.0.1\u{20}\u{20}", with: "Version: 1.2.0"))
                == true)
        #expect(updated?.hasSuffix("\n<!-- /okf:derived -->\n") == true)
    }

    @Test(arguments: [
        (openA + "\n<!-- okf:derived id=b source=deps -->\n" + close, "안에"),
        (openA + "\n" + close + "\n" + openA + "\n" + close, "겹침"),
        (openA + "\nx", "닫히지"),
        ("x\n" + close, "짝 없는"),
        ("<!-- okf:derived id=a -->\n" + close, "source"),
        ("<!-- okf:derived id=a source=nothing -->\n" + close, "모르는"),
    ])
    func reportsMarkerErrors(_ text: String, _ expected: String) throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (updated, problems) = OKF.sync(text, document: "apps/notes/README.md", kind: .app, root: root)

        #expect(updated == nil)
        #expect(problems.contains { $0.contains(expected) }, "\(problems)")
    }

    @Test func missingSourceIsAProblem() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appending(path: "apps/notes/VERSION"))

        #expect(OKF.plan(root: root).problems.contains { $0.contains("apps/notes/VERSION") })
    }
}

struct RootChecksTests {
    @Test func rootEntriesFollowWhatGitSees() throws {
        let fixture = try AdoptFixture()
        defer { fixture.cleanUp() }
        let target = fixture.target
        try fixture.write(".worktrees/\n", ".gitignore", in: target)
        try fixture.write("x\n", ".worktrees/branch/file.txt", in: target)
        try fixture.write("x\n", "swift/apps/old/README.md", in: target)
        try fixture.write("x\n", "notes.txt", in: target)

        #expect(RootChecks.unexpectedRootEntries(in: target) == ["notes.txt", "swift"])
    }

    @Test(arguments: ["notes", "memo-board", "image-resizer-2", "v2-sync"])
    func acceptsNames(_ name: String) {
        #expect(RootChecks.itemNameProblems(name, kind: "app").isEmpty)
    }

    @Test(arguments: [
        ("Notes", "app"), ("new-notes", "app"), ("notes-tmp", "app"), ("app-tools", "app"), ("notes-apps", "app"),
        ("shared-package", "package"), ("notes-2024", "app"), ("report-240712", "app"), ("notes-7-12", "app"),
    ])
    func rejectsNames(_ name: String, _ kind: String) {
        #expect(!RootChecks.itemNameProblems(name, kind: kind).isEmpty)
    }
}
