import Foundation
import Testing

@testable import RepoCore

struct SwiftVersionTests {
    @Test func parsesXcodeDriverOutput() {
        let output = """
            swift-driver version: 1.120.5 Apple Swift version 6.1 (swiftlang-6.1.0.110.21 clang-1700.0.13.3)
            Target: arm64-apple-macosx15.0
            """
        #expect(SemanticVersion.parseSwiftVersion(output) == SemanticVersion(major: 6, minor: 1, patch: 0))
    }

    @Test func parsesPatchVersion() {
        let output = """
            swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
            Target: arm64-apple-macosx26.0
            """
        #expect(SemanticVersion.parseSwiftVersion(output) == SemanticVersion(major: 6, minor: 3, patch: 3))
    }

    @Test func parsesOlderAndDevelopmentOutput() {
        #expect(
            SemanticVersion.parseSwiftVersion("Apple Swift version 5.10 (swiftlang-5.10.0.13 clang-1500.3.9.4)")
                == SemanticVersion(major: 5, minor: 10, patch: 0)
        )
        #expect(
            SemanticVersion.parseSwiftVersion("Swift version 6.2-dev (LLVM 1234, Swift 5678)")
                == SemanticVersion(major: 6, minor: 2, patch: 0)
        )
        #expect(SemanticVersion.parseSwiftVersion("command not found") == nil)
    }

    @Test func requiresSwift61() {
        func check(_ output: String) -> DoctorCheck.Status {
            Doctor.swiftCheck(ProcessResult(status: 0, standardOutput: output, standardError: "")).status
        }
        #expect(check("Apple Swift version 6.1 (swiftlang-6.1.0.110.21 clang-1700.0.13.3)") == .ok)
        #expect(check("Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)") == .fail)
        #expect(check("garbage") == .fail)
        #expect(Doctor.swiftCheck(nil).status == .fail)
    }
}

struct AppStructureTests {
    func makeApp(_ files: [String: String], directories: [String] = []) throws -> URL {
        let app = try TestSupport.makeTemporaryDirectory().appending(path: "memo-board", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        for (path, text) in files {
            try TestSupport.write(text, to: app.appending(path: path))
        }
        for directory in directories {
            let url = app.appending(path: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return app
    }

    @Test func completeAppPasses() throws {
        let app = try makeApp(
            ["Package.swift": "", "README.md": "", "VERSION": "0.1.0\n"],
            directories: ["Tests"]
        )
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let check = AppStructure.check(appDirectory: app)

        #expect(check.status == .ok)
        #expect(check.name == "app memo-board")
    }

    @Test func missingFilesFail() throws {
        let app = try makeApp(["Package.swift": ""])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let check = AppStructure.check(appDirectory: app)

        #expect(check.status == .fail)
        #expect(check.name == "app memo-board")
        #expect(check.detail.contains("README.md"))
        #expect(check.detail.contains("VERSION"))
        #expect(check.detail.contains("Tests/"))
        #expect(!check.detail.contains("Package.swift"))
    }

    @Test func malformedVersionFails() throws {
        let app = try makeApp(
            ["Package.swift": "", "README.md": "", "VERSION": "1.0\n"],
            directories: ["Tests"]
        )
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let check = AppStructure.check(appDirectory: app)

        #expect(check.status == .fail)
        #expect(check.detail.contains("VERSION"))
    }

    @Test func doctorReportsEveryApp() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestSupport.write("{\"bundlePrefix\": \"com.mycompany\"}", to: root.appending(path: "repo.json"))
        try TestSupport.write("", to: root.appending(path: "apps/.gitkeep"))
        try TestSupport.write("0.1.0", to: root.appending(path: "apps/broken/VERSION"))
        let repository = Repository(root: root)

        let checks = Doctor.appChecks(repository)

        #expect(checks.map(\.name) == ["app broken"])
        #expect(checks.first?.status == .fail)
    }

    @Test(arguments: [("0.1.0", true), ("10.20.30", true), ("1.0", false), ("1.0.0-beta", false), ("v1.0.0", false)])
    func validatesVersion(_ text: String, _ expected: Bool) {
        #expect(AppStructure.isValidVersion(text) == expected)
    }
}

struct RepositoryTests {
    @Test func locatesRootFromSubdirectory() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestSupport.write("{\"bundlePrefix\": \"com.example\"}", to: root.appending(path: "repo.json"))
        let nested = root.appending(path: "apps/notes/Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let repository = Repository.locate(from: nested)

        #expect(repository?.root.standardizedFileURL.path == root.standardizedFileURL.path)
    }

    @Test func placeholderPrefixWarnsAndBrokenConfigFails() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = Repository(root: root)
        let config = root.appending(path: "repo.json")

        try TestSupport.write("{\"bundlePrefix\": \"com.example\"}", to: config)
        #expect(Doctor.configCheck(repository).status == .warn)

        try TestSupport.write("{\"bundlePrefix\": \"com.mycompany\"}", to: config)
        #expect(Doctor.configCheck(repository).status == .ok)

        try TestSupport.write("{\"bundlePrefix\": \"not a domain\"}", to: config)
        #expect(Doctor.configCheck(repository).status == .fail)

        try TestSupport.write("{", to: config)
        #expect(Doctor.configCheck(repository).status == .fail)
    }
}
