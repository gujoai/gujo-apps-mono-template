import Foundation
import Testing

@testable import RepoCore

struct DocumentChecksTests {
    static let architecture = """
        <!-- template:begin -->
        # 구조
        ## 목적
        ## 폴더 배치
        ## 의존 방향
        ## 주요 흐름
        ## 경계
        ## 변경 규칙
        ### 독자
        ### 다시 읽기
        ### 점검 상태
        <!-- template:end -->
        """

    /// A repository whose documents pass every check.
    func makeRepository() throws -> Repository {
        let root = try TestSupport.makeTemporaryDirectory()
        try TestSupport.write(
            #"{"version": "0.1.0", "managedPaths": ["template.json"], "managedBlocks": ["AGENTS.md", "ARCHITECTURE.md"]}"#,
            to: root.appending(path: "template.json")
        )
        try TestSupport.write(Self.architecture, to: root.appending(path: "ARCHITECTURE.md"))
        try TestSupport.write(
            "<!-- template:begin -->\n[구조](ARCHITECTURE.md)\n<!-- template:end -->\n",
            to: root.appending(path: "AGENTS.md")
        )
        try TestSupport.write("[규칙](AGENTS.md), [결정](decisions/)\n", to: root.appending(path: "README.md"))
        try FileManager.default.createDirectory(
            at: root.appending(path: "decisions", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return Repository(root: root)
    }

    @Test func validDocumentsPass() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }

        let checks = DocumentChecks.checks(repository)

        #expect(checks.map(\.status) == [.ok, .ok, .ok, .ok], "\(checks)")
    }

    @Test func contextFilesOutsideTheRootFail() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let root = repository.root
        for path in [
            "apps/notes/AGENTS.md", "docs/claude.md", "templates/macos-app/AGENTS.md", ".build/debug/CLAUDE.md",
            "apps/notes/.build/x/AGENTS.md", "apps/notes/README.md",
        ] {
            try TestSupport.write("rules\n", to: root.appending(path: path))
        }

        #expect(DocumentChecks.misplacedContextFiles(in: root) == ["apps/notes/AGENTS.md", "docs/claude.md"])
        let check = DocumentChecks.contextFileCheck(repository)
        #expect(check.status == .fail)
        #expect(check.detail.contains("apps/notes/AGENTS.md"))
    }

    @Test func missingArchitectureHeadingsFail() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let text = Self.architecture.replacingOccurrences(of: "## 경계\n", with: "")
            .replacingOccurrences(of: "### 점검 상태\n", with: "### 점검\n")
        try TestSupport.write(text, to: repository.root.appending(path: "ARCHITECTURE.md"))

        #expect(
            DocumentChecks.missingHeadings(in: text, required: DocumentChecks.architectureHeadings) == [
                "## 경계", "### 점검 상태",
            ]
        )
        #expect(DocumentChecks.architectureCheck(repository).status == .fail)
    }

    @Test func missingReadmeOnlyWarns() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try FileManager.default.removeItem(at: repository.root.appending(path: "README.md"))

        #expect(DocumentChecks.linkCheck(repository).status == .warn)
    }

    @Test func missingArchitectureFails() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try FileManager.default.removeItem(at: repository.root.appending(path: "ARCHITECTURE.md"))

        #expect(DocumentChecks.architectureCheck(repository).status == .fail)
        #expect(DocumentChecks.templateBlockCheck(repository).status == .fail)
    }

    @Test func findsRelativeLinksOutsideCode() {
        let text = """
            [ok](README.md) and [dir](decisions/) and [frag](AGENTS.md#규칙) and [space](my%20file.md)
            [web](https://example.com/x.md) [mail](mailto:a@example.com) [anchor](#top)
            [titled](docs/guide.md "제목") ![image](images/a.png)
            `[inline](inline.md)` is code
            ```
            [fenced](fenced.md)
            ```
            """

        #expect(
            DocumentChecks.relativeLinks(in: text) == [
                "README.md", "decisions/", "AGENTS.md#규칙", "my%20file.md", "docs/guide.md", "images/a.png",
            ]
        )
    }

    @Test func brokenRelativeLinksFail() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try TestSupport.write("", to: repository.root.appending(path: "my file.md"))
        let text = "[a](AGENTS.md#x) [b](missing.md) [c](my%20file.md) [d](decisions/) [e](gone/)\n"

        #expect(DocumentChecks.brokenLinks(in: text, relativeTo: repository.root) == ["missing.md", "gone/"])

        try TestSupport.write(text, to: repository.root.appending(path: "README.md"))
        let check = DocumentChecks.linkCheck(repository)
        #expect(check.status == .fail)
        #expect(check.detail.contains("README.md → missing.md"))
    }

    @Test func unpairedTemplateMarkersFail() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try TestSupport.write(
            "<!-- template:begin -->\nno end marker\n",
            to: repository.root.appending(path: "AGENTS.md")
        )

        let check = DocumentChecks.templateBlockCheck(repository)

        #expect(check.status == .fail)
        #expect(check.detail.contains("AGENTS.md"))
    }
}
