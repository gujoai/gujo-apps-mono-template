import Foundation
import Testing

@testable import RepoCore

struct AppGeneratorTests {
    func hasPlaceholder(_ text: String) -> Bool {
        text.contains(/__[A-Za-z_]+__/)
    }

    /// A throwaway repository holding `repo.json` and a copy of the real template.
    func makeRepository(bundlePrefix: String) throws -> Repository {
        let root = try TestSupport.makeTemporaryDirectory()
        try TestSupport.write("{\"bundlePrefix\": \"\(bundlePrefix)\"}\n", to: root.appending(path: "repo.json"))
        let repository = Repository(root: root)
        try FileManager.default.createDirectory(
            at: repository.templateDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: try TestSupport.realRepository().templateDirectory,
            to: repository.templateDirectory
        )
        try FileManager.default.createDirectory(at: repository.appsDirectory, withIntermediateDirectories: true)
        return repository
    }

    /// Paths of every file and directory under `directory`, relative to it.
    func relativePaths(under directory: URL) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()
    }

    @Test func templateUsesEveryPlaceholder() throws {
        let template = try TestSupport.realRepository().templateDirectory
        var combined = try relativePaths(under: template).joined(separator: "\n")
        for path in try relativePaths(under: template) {
            combined += (try? String(contentsOf: template.appending(path: path), encoding: .utf8)) ?? ""
        }
        for token in ["__NAME__", "__name__", "__DISPLAY_NAME__", "__BUNDLE_ID__", "__DATA_ENV__"] {
            #expect(combined.contains(token), "template never uses \(token)")
        }
    }

    @Test func generatedAppHasNoPlaceholdersLeft() throws {
        let repository = try makeRepository(bundlePrefix: "com.mycompany")
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let names = try AppNames(slug: "memo-board", bundlePrefix: "com.mycompany")

        let app = try AppGenerator.generate(names, in: repository)

        for path in try relativePaths(under: app) {
            #expect(!hasPlaceholder(path), "placeholder left in name: \(path)")
            let url = app.appending(path: path)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                #expect(!hasPlaceholder(text), "placeholder left in \(path)")
            }
        }
    }

    @Test func generatedAppUsesDerivedNames() throws {
        let repository = try makeRepository(bundlePrefix: "com.mycompany")
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let names = try AppNames(slug: "memo-board", bundlePrefix: "com.mycompany")

        let app = try AppGenerator.generate(names, in: repository)

        let paths = Set(try relativePaths(under: app))
        for expected in [
            "Package.swift", "README.md", "VERSION", "Packaging/Info.plist", "Sources/MemoBoardCore",
            "Sources/MemoBoardApp", "Sources/MemoBoardCLI", "Tests/MemoBoardCoreTests",
        ] {
            #expect(paths.contains(expected), "missing \(expected)")
        }
        let manifest = try String(contentsOf: app.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains("\"MemoBoardApp\""))
        #expect(manifest.contains("\"memo-board\""))
        let plist = try AppStructure.readInfoPlist(appDirectory: app)
        #expect(plist["CFBundleIdentifier"] as? String == "com.mycompany.memo-board")
        #expect(plist["CFBundleDisplayName"] as? String == "Memo Board")
        #expect(plist["CFBundleExecutable"] as? String == "MemoBoardApp")
        #expect(AppStructure.readVersion(appDirectory: app) == "0.1.0")
        let everything = try relativePaths(under: app).compactMap {
            try? String(contentsOf: app.appending(path: $0), encoding: .utf8)
        }
        .joined()
        #expect(everything.contains("MEMO_BOARD_DATA_DIR"))
        #expect(AppStructure.check(appDirectory: app).status == .ok)
    }

    @Test func singleWordSlugKeepsProductNamesApart() throws {
        let repository = try makeRepository(bundlePrefix: "com.example")
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let names = try AppNames(slug: "notes", displayName: "My Notes", bundlePrefix: "com.example")

        let app = try AppGenerator.generate(names, in: repository)

        let manifest = try String(contentsOf: app.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains(".executable(name: \"NotesApp\""))
        #expect(manifest.contains(".executable(name: \"notes\""))
        let plist = try AppStructure.readInfoPlist(appDirectory: app)
        #expect(plist["CFBundleDisplayName"] as? String == "My Notes")
    }

    @Test func refusesExistingApp() throws {
        let repository = try makeRepository(bundlePrefix: "com.example")
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let names = try AppNames(slug: "notes", bundlePrefix: "com.example")
        try AppGenerator.generate(names, in: repository)

        let error = #expect(throws: RepoError.self) {
            try AppGenerator.generate(names, in: repository)
        }
        #expect(error?.exitCode == ExitCode.failure)
    }
}
