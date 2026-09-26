import Foundation
import Testing

@testable import RepoCore

struct TemplateTagTests {
    @Test func parsesAndSortsVersionTags() {
        let output = """
            1111111111111111111111111111111111111111\trefs/tags/v0.9.1
            2222222222222222222222222222222222222222\trefs/tags/v0.10.0
            3333333333333333333333333333333333333333\trefs/tags/v0.1.0
            4444444444444444444444444444444444444444\trefs/tags/v1.0
            5555555555555555555555555555555555555555\trefs/tags/1.0.0
            6666666666666666666666666666666666666666\trefs/tags/v1.0.0-rc1
            7777777777777777777777777777777777777777\trefs/tags/release
            8888888888888888888888888888888888888888\trefs/tags/v0.2.0^{}
            9999999999999999999999999999999999999999\trefs/heads/v9.9.9
            """

        let versions = TemplateSource.parseTags(output)

        #expect(versions.map(\.description) == ["0.1.0", "0.9.1", "0.10.0"])
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.9.1")!)
    }

    @Test func emptyOutputHasNoVersions() {
        #expect(TemplateSource.parseTags("").isEmpty)
    }

    @Test func keepsRemoteSourcesAndResolvesLocalPaths() {
        let base = URL(fileURLWithPath: "/tmp/work", isDirectory: true)
        let https = "https://github.com/org/app-template.git"
        let scp = "git@github.com:org/app-template.git"
        #expect(TemplateSource.resolve(https, relativeTo: base) == https)
        #expect(TemplateSource.resolve(scp, relativeTo: base) == scp)
        #expect(TemplateSource.resolve("../template", relativeTo: base) == "/tmp/template")
        #expect(TemplateSource.resolve("/srv/template/", relativeTo: base) == "/srv/template")
    }

    @Test func parsesPorcelainPaths() {
        let output = " M AGENTS.md\0?? tools/repo/new file.txt\0R  new.txt\0old.txt\0 D docs/decisions/README.md\0"
        #expect(
            Git.parsePorcelain(output) == [
                "AGENTS.md", "tools/repo/new file.txt", "new.txt", "docs/decisions/README.md",
            ]
        )
    }
}

struct ManagedBlockTests {
    @Test func replacesOnlyTheBlock() throws {
        let current = """
            # Customer title
            before the block stays
            <!-- template:begin -->
            old rule 1
            old rule 2
            <!-- template:end -->

            ## 이 저장소의 규칙
            - customer line
            """
        let template = """
            anything above is ignored
            <!-- template:begin -->
            new rule
            <!-- template:end -->
            anything below is ignored
            """

        let result = try ManagedBlock.replacingBlock(in: current, with: template, file: "AGENTS.md")

        #expect(
            result == """
                # Customer title
                before the block stays
                <!-- template:begin -->
                new rule
                <!-- template:end -->

                ## 이 저장소의 규칙
                - customer line
                """
        )
    }

    @Test func keepsTrailingTextByteForByte() throws {
        let current = "<!-- template:begin -->\nold\n<!-- template:end -->\n\n  trailing  spaces \n\n"
        let template = "<!-- template:begin -->\nnew\n<!-- template:end -->\n"

        let result = try ManagedBlock.replacingBlock(in: current, with: template, file: "AGENTS.md")

        #expect(result == "<!-- template:begin -->\nnew\n<!-- template:end -->\n\n  trailing  spaces \n\n")
    }

    @Test(arguments: [
        "no markers at all\n",
        "<!-- template:begin -->\nonly begin\n",
        "only end\n<!-- template:end -->\n",
        "<!-- template:end -->\nreversed\n<!-- template:begin -->\n",
        "<!-- template:begin -->\n<!-- template:begin -->\ntwice\n<!-- template:end -->\n",
        "<!-- template:begin -->\na\n<!-- template:end -->\n<!-- template:begin -->\nb\n<!-- template:end -->\n",
    ])
    func rejectsMissingOrUnpairedMarkers(_ text: String) {
        let valid = "<!-- template:begin -->\nx\n<!-- template:end -->\n"
        #expect(throws: RepoError.self) {
            try ManagedBlock.replacingBlock(in: text, with: valid, file: "AGENTS.md")
        }
        #expect(throws: RepoError.self) {
            try ManagedBlock.replacingBlock(in: valid, with: text, file: "AGENTS.md")
        }
    }
}

struct TemplateManifestTests {
    func manifest(_ json: String) throws -> TemplateManifest {
        try TemplateManifest.decode(Data(json.utf8))
    }

    @Test func decodesManifest() throws {
        let manifest = try manifest(
            #"{"version": "0.2.0", "managedPaths": ["tools/repo", "template.json"], "managedBlocks": ["AGENTS.md"]}"#
        )
        #expect(manifest.semanticVersion == SemanticVersion(major: 0, minor: 2, patch: 0))
        #expect(manifest.managedPaths == ["tools/repo", "template.json"])
    }

    @Test(arguments: [
        "{",
        #"{"version": "0.1.0"}"#,
        #"{"version": "0.1", "managedPaths": [], "managedBlocks": []}"#,
        #"{"version": "v0.1.0", "managedPaths": [], "managedBlocks": []}"#,
        #"{"version": 1, "managedPaths": [], "managedBlocks": []}"#,
    ])
    func rejectsMalformedManifest(_ json: String) {
        #expect(throws: RepoError.self) {
            try manifest(json)
        }
    }

    @Test(arguments: [
        "/etc", "../outside", "tools/../apps", "apps", "apps/notes", ".git/config", "", ".", "tools//repo",
    ])
    func rejectsUnsafePaths(_ path: String) {
        #expect(!TemplateManifest.isSafePath(path))
        let json = #"{"version": "0.1.0", "managedPaths": ["\#(path)"], "managedBlocks": []}"#
        #expect(throws: RepoError.self) {
            try manifest(json)
        }
    }

    @Test(arguments: ["Package.swift", "tools/repo", "docs/decisions/README.md", ".swift-format", "appstore/notes"])
    func acceptsSafePaths(_ path: String) {
        #expect(TemplateManifest.isSafePath(path))
    }

    @Test func missingManifestFails() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: RepoError.self) {
            try TemplateManifest.load(from: directory)
        }
    }

    @Test func unionAndRemovedPaths() {
        let current = TemplateManifest(
            version: "0.1.0",
            managedPaths: ["template.json", "tools/repo", "docs/decisions/README.md"],
            managedBlocks: ["AGENTS.md"]
        )
        let target = TemplateManifest(
            version: "0.2.0",
            managedPaths: ["template.json", "tools/repo", "tools/lint"],
            managedBlocks: ["AGENTS.md"]
        )

        #expect(
            TemplateUpdater.targets(current: current, target: target) == [
                "template.json", "tools/repo", "docs/decisions/README.md", "tools/lint", "AGENTS.md",
            ]
        )
        #expect(TemplateUpdater.removedPaths(current: current, target: target) == ["docs/decisions/README.md"])
        #expect(TemplateUpdater.removedPaths(current: target, target: current) == ["tools/lint"])
    }
}
